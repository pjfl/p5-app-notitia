package App::Notitia::Utilities;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE OK SLOT_TYPE_ENUM TRUE );
use App::Notitia::Util      qw( event_handler_cache load_file_data local_dt
                                locd new_request now_dt slot_limit_index );
use Class::Usul::Functions  qw( io is_member sum throw );
use Class::Usul::File;
use Class::Usul::Types      qw( Bool HashRef LoadableClass Object );
use Unexpected::Functions   qw( PathNotFound Unspecified );
use Web::Components::Util   qw( load_components );
use Moo;
use Class::Usul::Options;

extends q(Class::Usul::Programs);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);

has 'components' => is => 'lazy', isa => HashRef[Object], builder => sub {
   return load_components 'Model', application => $_[ 0 ];
};

with q(App::Notitia::Role::EventStream);

# Override default in base class
has '+config_class' => default => 'App::Notitia::Config';

# Public attributes
option 'all' => is => 'ro', isa => Bool, default => FALSE, short => 'a',
   documentation => 'Show all event attributes including the private ones';

has 'formatter' => is => 'lazy', isa => Object, builder => sub {
   $_[ 0 ]->formatter_class->new
      ( tab_width => $_[ 0 ]->config->mdn_tab_width ) };

has 'formatter_class' => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default => 'App::Notitia::Markdown';

has 'geolocator' => is => 'lazy', isa => Object, builder => sub {
   $_[ 0 ]->geolocator_class->new( $_[ 0 ]->config->geolocation ) };

has 'geolocator_class' => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default => 'App::Notitia::GeoLocation';

option 'not_enabled' => is => 'ro', isa => Bool, default => FALSE,
   documentation => 'Show only the event attributes that are not enabled';

has 'sms_sender_class' => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default => 'App::Notitia::SMS';

# Private functions
my $_slots_wanted = sub {
   my ($limits, $rota_dt, $role) = @_;

   my $day_max = sum( map { $limits->[ slot_limit_index 'day', $_ ] }
                      $role );
   my $night_max = sum( map { $limits->[ slot_limit_index 'night', $_ ] }
                        $role );
   my $wd = $night_max;
   my $we = $day_max + $night_max;

   return (0, $wd, $wd, $wd, $wd, $wd, $we, $we)[ $rota_dt->day_of_week ];
};

# Private methods
my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

my $_assigned_slots = sub {
   my ($self, $req, $rota_name, $rota_dt) = @_;

   my $opts     =  {
      after     => $rota_dt->clone->subtract( days => 1 ),
      before    => $rota_dt->clone->add( days => 1 ),
      rota_type => $self->$_find_rota_type( $rota_name )->id };
   my $slot_rs  =  $self->schema->resultset( 'Slot' );
   my $data     =  {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      $data->{ locd( $req, $slot->start_date ).'_'.$slot->key } = $slot;
   }

   return $data;
};

my $_list_from_stash = sub {
   my ($self, $stash) = @_; my ($person, $role, $scode);

   my $person_rs = $self->schema->resultset( 'Person' );

   $scode = $stash->{shortcode}
      and $person = $person_rs->find_by_shortcode( $scode )
      and return [ [ $person->label, $person ] ];

   my $opts = { columns => [ 'email_address', 'mobile_phone' ] };
   my $ss = $stash->{status};

   $opts->{status} = $ss && $ss eq 'all' ? undef : $ss ? $ss : 'current';

   $stash->{role} or throw Unspecified, [ 'person role' ];

   return $person_rs->list_people( $stash->{role}, $opts );
};

my $_list_participents = sub {
   my $self  = shift;
   my $uri   = $self->options->{event};
   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $opts  = { columns => [ 'email_address', 'mobile_phone' ] };
   my $rs    = $self->schema->resultset( 'Person' );

   return $rs->list_participents( $event, $opts );
};

my $_list_people = sub {
   my $self = shift;
   my $rs   = $self->schema->resultset( 'Person' );
   my $opts = { columns => [ 'email_address', 'mobile_phone' ] };
   my $role = $self->options->{role};

   $self->options->{status} and $opts->{status} = $self->options->{status};

   return $role ? $rs->list_people( $role, $opts )
                : $rs->list_all_people( $opts );
};

my $_list_recipients = sub {
   my $self = shift; my $path = io $self->options->{recipients};

   ($path->exists and $path->is_file) or throw PathNotFound, [ $path ];

   my $data = Class::Usul::File->data_load
      ( paths => [ $path ], storage_class => 'JSON' ) // {}; $path->unlink;
   my $rs   = $self->schema->resultset( 'Person' );

   return [ map { [ $_->label, $_ ] }
            map { $rs->find_by_shortcode( $_ ) }
               @{ $data->{selected} // [] } ];
};

my $_load_stash = sub {
   my ($self, $plate_name, $quote) = @_; my $stash = {};

   if ($self->options->{stash}) {
      my $path = io $self->options->{stash};

      ($path->exists and $path->is_file) or throw PathNotFound, [ $path ];
      $stash = Class::Usul::File->data_load
         ( paths => [ $path ], storage_class => 'JSON' ) // {};
      $path->unlink;
   }

   $stash->{app_name} = $self->config->title;
   $stash->{path} = io $plate_name;
   $stash->{sms_attributes} = { quote => $quote };

   my $template = load_file_data( $stash );

   $plate_name =~ m{ \.md \z }mx
      and $template = $self->formatter->markdown( $template );

   return $stash, $template;
};

my $_new_request = sub {
   my ($self, $scheme, $hostport) = @_;

   return new_request $self->config, $self->locale, $scheme, $hostport;
};

my $_qualify_assets = sub {
   my ($self, $files) = @_; $files or return FALSE; my $assets = {};

   for my $file (@{ $files }) {
      my $path = $self->config->assetdir->catfile( $file );

      $path->exists or $path = io $file; $path->exists or next;

      $assets->{ $path->basename } = $path;
   }

   return $assets;
};

my $_template_path = sub {
   my ($self, $name) = @_; my $conf = $self->config;

   my $file = $conf->template_dir->catfile( "custom/${name}.tt" );

   return $file->exists ? "custom/${name}.tt" : $conf->skin."/${name}.tt";
};

my $_send_email = sub {
   my ($self, $stash, $template, $person, $attaches) = @_;

   $self->config->no_message_send and $self->info
      ( 'Would email [_1]', { args => [ $person->label ] } ) and return;

   $person->email_address =~ m{ \@ example\.com \z }imx and $self->info
      ( 'Will not email [_1] example address', {
         args => [ $person->label ] } ) and return;

   my $action; $action = $stash->{action}
      and $person->has_stopped_email( $action ) and $self->info
         ( 'Would email [_1] [_2]', { args => [ $person->label, $action ] } )
         and return;

   my $layout = $self->$_template_path( 'email_layout' );

   $template = "[% WRAPPER '${layout}' %]${template}[% END %]";

   $stash = { %{ $stash } };
   $stash->{first_name} = $person->first_name;
   $stash->{label     } = $person->label;
   $stash->{last_name } = $person->last_name;
   $stash->{username  } = $person->name;

   my $post = {
      attributes      => {
         charset      => $self->config->encoding,
         content_type => 'text/html', },
      from            => $self->config->email_sender,
      stash           => $stash,
      subject         => $stash->{subject} // 'No subject',
      template        => \$template,
      to              => $person->email_address, };

   $attaches and $post->{attachments} = $attaches;

   my $r      = $self->send_email( $post );
   my ($id)   = $r =~ m{ ^ OK \s+ id= (.+) $ }msx; chomp $id;
   my $params = { args => [ $person->shortcode, $id ] };

   $self->info( 'Emailed [_1] - [_2]', $params );
   return;
};

my $_send_sms = sub {
   my ($self, $stash, $template, $tuples) = @_; my $conf = $self->config;

   my $attr = { %{ $conf->sms_attributes }, %{ $stash->{sms_attributes} } };

   $stash->{template}->{layout} = \$template;

   my $message = $self->render_template( $stash ); my @recipients;

   $self->info( "SMS message: ${message}" ); my $action = $stash->{action};

   for my $person (map { $_->[ 1 ] } @{ $tuples }) {
      $action and $person->has_stopped_sms( $action ) and $self->info
         ( 'Would SMS [_1] [_2]', { args => [ $person->label, $action ] } )
         and next;
      $self->log->debug( 'SMS recipient: '.$person->shortcode );
      $person->mobile_phone and push @recipients,
         map { s{ \A 07 }{447}mx; $_ } $person->mobile_phone;
   }

   $conf->no_message_send and $self->info( 'SMS turned off in config' )
      and return;

   $attr->{log     } //= $self->log;
   $attr->{password} //= 'unknown';
   $attr->{username} //= 'unknown';

   my $uri = $stash->{quote_uri}; $uri and $attr->{quote} = TRUE;
   my $sender = $self->sms_sender_class->new( $attr );
   my $rv = $sender->send_sms( $message, @recipients );

   $uri and $message = "action:received-sms-quote quote_uri:${uri} "
                     . "quote_value:${rv}"
        and $self->send_event( $self->$_new_request, $message );

   $self->info( 'SMS message rv: [_1]', { args => [ $rv ] } );
   return;
};

# Public methods
sub application_upgraded : method {
   my $self    = shift;
   my $req     = $self->$_new_request( $self->next_argv, $self->next_argv );
   my $now     = local_dt now_dt;
   my $dmy     = locd $req, $now;
   my $time    = sprintf '%.2d.%.2d', $now->hour, $now->minute;
   my $version = $self->config->appclass->VERSION;
   my $message = "action:application-upgraded date:${dmy} time:${time} "
               . "version:${version}";

   $self->components; $self->send_event( $req, $message );

   return OK;
}

sub dump_event_attr : method {
   my $self = shift; $self->plugins; my $cache = event_handler_cache;

   for my $stream (keys %{ $cache }) {
      my $allowed = $self->config->automated->{ $stream } // [];
      my @keys = keys %{ $cache->{ $stream } };

      for my $action (@keys) {
         $self->not_enabled and is_member $action, $allowed
            and delete $cache->{ $stream }->{ $action };

         not $self->all and $action =~ m{ \A _ }mx
            and delete $cache->{ $stream }->{ $action };
      }
   }

   $self->dumper( $cache );
   return OK;
}

sub geolocation : method {
   my $self = shift;
   my $object_type = $self->next_argv or throw Unspecified, [ 'object type' ];
   my $id = $self->next_argv or throw Unspecified, [ 'id' ];

   $self->info( 'Geolocating [_1] [_2]', { args => [ $object_type, $id ] } );

   my $rs = $self->schema->resultset( $object_type );
   my $object = $object_type eq 'Person'
              ? $rs->find_by_shortcode( $id ) : $rs->find( $id );
   my $postcode = $object->postcode;
   my $data = $self->geolocator->find_by_postcode( $postcode );
   my $coords = defined $data->{coordinates}
              ? $object->coordinates( $data->{coordinates} ) : 'undefined';
   my $location = defined $data->{location}
                ? $object->location( $data->{location} ) : 'undefined';

   (defined $data->{coordinates} or defined $data->{location})
      and $object->update;
   $self->info( 'Located [_1] [_2]: [_3] [_4] [_5]', {
      args => [ $object_type, $id, $postcode, $coords, $location ] } );
   return OK;
}

sub impending_slot : method {
   my $self = shift; $self->components;
   my $scheme = $self->next_argv;
   my $hostport = $self->next_argv;
   my $days = $self->next_argv // 3;
   my $rota_name = $self->next_argv // 'main';
   my $rota_dt = now_dt->add( days => $days );
   my $req = $self->$_new_request( $scheme, $hostport );
   my $data = $self->$_assigned_slots( $req, $rota_name, $rota_dt );
   my $dmy = locd $req, $rota_dt;
   my $ymd = local_dt( $rota_dt )->ymd;
   my $sent = FALSE;

   for my $key (grep { $_ =~ m{ \A $ymd _ }mx } sort keys %{ $data }) {
      my $slot_key = $data->{ $key }->key;
      my $scode = $data->{ $key }->operator;
      my $message = "action:impending-slot date:${dmy} days_in_advance:${days} "
                  . "shortcode:${scode} rota_name:${rota_name} "
                  . "rota_date:${ymd} slot_key:${slot_key}";

      $self->send_event( $req, $message ); $sent = TRUE;
   }

   $sent and $self->info( "Sent impending slot emails for ${dmy}" );

   return OK;
}

sub send_message : method {
   my $self       = shift;
   my $conf       = $self->config;
   my $opts       = $self->options;
   my $sink       = $self->next_argv or throw Unspecified, [ 'message sink' ];
   my $plate_name = $self->next_argv or throw Unspecified, [ 'template name' ];
   my $quote      = $self->next_argv ? TRUE : $opts->{quote} ? TRUE : FALSE;

   my ($stash, $template) = $self->$_load_stash( $plate_name, $quote );

   my $attaches = $self->$_qualify_assets( delete $stash->{attachments} );
   my $tuples   = $opts->{stash}      ? $self->$_list_from_stash( $stash )
                : $opts->{event}      ? $self->$_list_participents
                : $opts->{recipients} ? $self->$_list_recipients
                                      : $self->$_list_people;

   if ($sink eq 'email') {
      for my $person (map { $_->[ 1 ] } @{ $tuples }) {
         $self->$_send_email( $stash, $template, $person, $attaches );
      }
   }
   elsif ($sink eq 'sms') { $self->$_send_sms( $stash, $template, $tuples ) }
   else { throw 'Message sink [_1] unknown', [ $sink ] }

   $conf->sessdir eq substr $plate_name, 0, length $conf->sessdir
      and unlink $plate_name;

   return OK;
}

sub vacant_slot : method {
   my $self = shift; $self->components;
   my $scheme = $self->next_argv;
   my $hostport = $self->next_argv;
   my $days = $self->next_argv // 7;
   my $rota_name = $self->next_argv // 'main';
   my $rota_dt = now_dt->add( days => $days );
   my $req = $self->$_new_request( $scheme, $hostport );
   my $data = $self->$_assigned_slots( $req, $rota_name, $rota_dt );
   my $limits = $self->config->slot_limits;
   my $dmy = locd $req, $rota_dt;
   my $ymd = local_dt( $rota_dt )->ymd;

   for my $slot_type (@{ SLOT_TYPE_ENUM() }) {
      my $wanted = $_slots_wanted->( $limits, $rota_dt, $slot_type );
      my $slots_claimed = grep { $_ =~ m{ _ $slot_type _ }mx }
                          grep { $_ =~ m{ \A $ymd _ }mx } keys %{ $data };

      $slots_claimed >= $wanted and next;

      my $message = "action:vacant-slot date:${dmy} days_in_advance:${days} "
                  . "rota_name:${rota_name} rota_date:${ymd} "
                  . "slot_type:${slot_type}";

      $self->send_event( $req, $message );
      $self->info( "Sending vacant ${slot_type} slot emails for ${dmy}" );
   }

   return OK;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Utilities - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Utilities;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head2 C<application_upgraded> - Generates the application upgraded email

=head2 C<dump_event_attr> - Dumps the event handling attribute data

=head2 C<geolocation> - Lookup geolocation information

=head2 C<impending_slot> - Generates the impending slots email

   bin/notitia-util -q impending-slot [scheme] [hostport]

Run this from cron(8) to periodically trigger the impending slots email

=head2 C<send_message> - Send email or SMS to people

=head2 C<vacant_slot> - Generates the vacant slots email

   bin/notitia-util -q vacant-slot [scheme] [hostport]

Run this from cron(8) to periodically trigger the vacant slots email

=head1 Diagnostics

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Notitia.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2016 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
