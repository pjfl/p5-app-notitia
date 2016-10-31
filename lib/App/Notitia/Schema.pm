package App::Notitia::Schema;

use namespace::autoclean;

use App::Notitia; our $VERSION = $App::Notitia::VERSION;

use App::Notitia::Constants qw( AS_PASSWORD EXCEPTION_CLASS FALSE
                                NUL OK SLOT_TYPE_ENUM TRUE );
use App::Notitia::GeoLocation;
use App::Notitia::SMS;
use App::Notitia::Util      qw( encrypted_attr load_file_data local_dt
                                mail_domain now_dt slot_limit_index );
use Archive::Tar::Constant  qw( COMPRESS_GZIP );
use Class::Usul::Functions  qw( ensure_class_loaded io sum throw );
use Class::Usul::File;
use Class::Usul::Types      qw( HashRef LoadableClass
                                NonEmptySimpleStr Object );
use Unexpected::Functions   qw( PathNotFound Unspecified );
use Web::Components::Util   qw( load_components );
use Web::ComposableRequest;
use Moo;

extends q(Class::Usul::Schema);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);
with    q(Web::Components::Role::TT);

has 'components' => is => 'lazy', isa => HashRef[Object], builder => sub {
   return load_components 'Model', application => $_[ 0 ];
};

with q(App::Notitia::Role::EventStream);

# Attribute constructors
my $_build_admin_password = sub {
   my $self = shift; my $prompt = '+Database administrator password';

   return encrypted_attr $self->config, $self->config->ctlfile,
             'admin_password', sub { $self->get_line( $prompt, AS_PASSWORD ) };
};

# Public attributes (override defaults in base class)
has 'admin_password'  => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => $_build_admin_password;

has '+config_class'   => default => 'App::Notitia::Config';

has '+database'       => default => sub { $_[ 0 ]->config->database };

has 'formatter'       => is => 'lazy', isa => Object, builder => sub {
   $_[ 0 ]->formatter_class->new
      ( tab_width => $_[ 0 ]->config->mdn_tab_width ) };

has 'formatter_class' => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default            => 'App::Notitia::Markdown';

has 'jobdaemon'       => is => 'lazy', isa => Object, builder => sub {
   $_[ 0 ]->jobdaemon_class->new( {
      appclass => $_[ 0 ]->config->appclass,
      config   => { name => 'jobdaemon' },
      noask    => TRUE } ) };

has 'jobdaemon_class' => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default            => 'App::Notitia::JobDaemon';

has '+schema_classes' => default => sub { $_[ 0 ]->config->schema_classes };

has '+schema_version' => default => sub { App::Notitia->schema_version.NUL };

# Construction
sub BUILD {
   my $self = shift;
   my $conf = $self->config;
   my $file = $conf->logsdir->catfile( 'activity.log' );
   my $opts = { appclass => 'activity', builder => $self, logfile => $file, };

   $self->log_class->new( $opts );

   return;
}

around 'deploy_file' => sub {
   my ($orig, $self, @args) = @_;

   $self->config->appclass->env_var( 'bulk_insert', TRUE );

   return $orig->( $self, @args );
};

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
   my ($self, $rota_name, $rota_dt) = @_;

   my $slot_rs  =  $self->schema->resultset( 'Slot' );
   my $opts     =  {
      after     => $rota_dt->clone->subtract( days => 1 ),
      before    => $rota_dt->clone->add( days => 1 ),
      rota_type => $self->$_find_rota_type( $rota_name )->id };
   my $data     =  {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      $data->{ local_dt( $slot->start_date )->ymd.'_'.$slot->key } = $slot;
   }

   return $data;
};

my $_connect_attr = sub {
   return { %{ $_[ 0 ]->connect_info->[ 3 ] }, %{ $_[ 0 ]->db_attr } };
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

my $_load_from_stash = sub {
   my ($self, $stash) = @_; my ($person, $role, $scode);

   my $person_rs = $self->schema->resultset( 'Person' );

   $scode = $stash->{shortcode}
      and $person = $person_rs->find_by_shortcode( $scode )
      and return [ [ $person->label, $person ] ];

   my $opts = { columns => [ 'email_address', 'mobile_phone' ] };

   $stash->{status} and $opts->{status} = $stash->{status};

   $role = $stash->{role}
      and return $person_rs->list_people( $role, $opts );

   return $person_rs->list_all_people( $opts );
};

my $_load_stash = sub {
   my ($self, $plate_name, $quote) = @_; my $path = io $self->options->{stash};

   ($path->exists and $path->is_file) or throw PathNotFound, [ $path ];

   my $stash = Class::Usul::File->data_load
      ( paths => [ $path ], storage_class => 'JSON' ) // {}; $path->unlink;

   $stash->{app_name} = $self->config->title;
   $stash->{path} = io $plate_name;
   $stash->{sms_attributes} = { quote => $quote };

   my $template = load_file_data( $stash );

   $plate_name =~ m{ \.md \z }mx
      and $template = $self->formatter->markdown( $template );

   return $stash, $template;
};

my $_load_template = sub {
   my ($self, $plate_name, $quote) = @_;

   my $stash = { app_name => $self->config->title,
                 path => io( $plate_name ),
                 sms_attributes => { quote => $quote }, };
   my $template = load_file_data( $stash );

   $plate_name =~ m{ \.md \z }mx
      and $template = $self->formatter->markdown( $template );

   return $stash, $template;
};

my $_new_request = sub {
   my ($self, $scheme, $hostport) = @_;

   my $env = { HTTP_ACCEPT_LANGUAGE => $self->locale,
               HTTP_HOST => $hostport,
               SCRIPT_NAME => $self->config->mount_point,
               'psgi.url_scheme' => $scheme,
               'psgix.session' => { username => 'admin' } };
   my $factory = Web::ComposableRequest->new( config => $self->config );

   return $factory->new_from_simple_request( {}, '', {}, $env );
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
      ( 'Would not email [_1] example address', {
         args => [ $person->label ] } ) and return;

   my $action; $action = $stash->{action}
      and $person->has_stopped_email( $action ) and $self->info
         ( 'Would email [_1] [_2]', { args => [ $person->label, $action ] } )
         and return;

   my $layout = $self->$_template_path( 'email_layout' );

   $template = "[% WRAPPER '${layout}' %]${template}[% END %]";

   $stash->{first_name} = $person->first_name;
   $stash->{label     } = $person->label;
   $stash->{last_name } = $person->last_name;
   $stash->{username  } = $person->name;

   my $post = {
      attributes      => {
         charset      => $self->config->encoding,
         content_type => 'text/html', },
      from            => $self->config->title.'@'.mail_domain(),
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

   my $sender = App::Notitia::SMS->new( $attr );
   my $rv = $sender->send_sms( $message, @recipients );

   $self->info( 'SMS message rv: [_1]', { args => [ $rv ] } );
   return;
};

# Public methods
sub backup_data : method {
   my $self = shift;
   my $now  = now_dt;
   my $conf = $self->config;
   my $date = $now->ymd( NUL ).'-'.$now->hms( NUL );
   my $file = $self->database."-${date}.sql";
   my $path = $conf->tempdir->catfile( $file );
   my $bdir = $conf->vardir->catdir( 'backups' );
   my $tarb = $conf->title."-${date}.tgz";
   my $out  = $bdir->catfile( $tarb )->assert_filepath;

   if (lc $self->driver eq 'mysql') {
      $self->run_cmd
         ( [ 'mysqldump', '--opt', '--host', $self->host,
             '--password='.$self->admin_password, '--result-file',
             $path->pathname, '--user', $self->db_admin_ids->{mysql},
             '--databases', $self->database ] );
   }

   ensure_class_loaded 'Archive::Tar'; my $arc = Archive::Tar->new;

   chdir $conf->appldir;
   $path->exists and $arc->add_files( $path->abs2rel( $conf->appldir ) );

   for my $doc ($conf->docs_root->clone->deep->all_files) {
      $arc->add_files( $doc->abs2rel( $conf->appldir ) );
   }

   for my $cfgfile (map { io $_ } @{ $conf->cfgfiles }) {
      $arc->add_files( $cfgfile->abs2rel( $conf->appldir ) );
   }

   my $localedir = $conf->localedir
                        ->clone->filter( sub { m{ _local\.po \z }mx } )->deep;

   for my $pofile ($localedir->all_files ) {
      $arc->add_files( $pofile->abs2rel( $conf->appldir ) );
   }

   $self->info( 'Generating backup [_1]', { args => [ $tarb ] } );
   $arc->write( $out->pathname, COMPRESS_GZIP ); $path->unlink;

   return OK;
}

sub create_ddl : method {
   my $self = shift; $self->db_attr->{ignore_version} = TRUE;

   return $self->SUPER::create_ddl;
}

sub dump_connect_attr : method {
   my $self = shift; $self->dumper( $self->connect_info ); return OK;
}

sub deploy_and_populate : method {
   my $self    = shift; $self->db_attr->{ignore_version} = TRUE;
   my $rv      = $self->SUPER::deploy_and_populate;
   my $type_rs = $self->schema->resultset( 'Type' );
   my $sc_rs   = $self->schema->resultset( 'SlotCriteria' );

   for my $slot_type (@{ SLOT_TYPE_ENUM() }) {
      for my $cert_name (@{ $self->config->slot_certs->{ $slot_type } }) {
         my $cert = $type_rs->find_certification_by( $cert_name );

         $sc_rs->create( { slot_type             => $slot_type,
                           certification_type_id => $cert->id } );
      }
   }

   return $rv;
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
   my $locator = App::Notitia::GeoLocation->new( $self->config->geolocation );
   my $data = $locator->find_by_postcode( $postcode );
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
   my $self = shift;
   my $scheme = $self->next_argv // 'https';
   my $hostport = $self->next_argv // 'localhost:5000';
   my $days = $self->next_argv // 3;
   my $rota_name = $self->next_argv // 'main';
   my $rota_dt = now_dt->add( days => $days );
   my $data = $self->$_assigned_slots( $rota_name, $rota_dt );
   my $req = $self->$_new_request( $scheme, $hostport );
   my $dmy = local_dt( $rota_dt )->dmy( '/' );
   my $ymd = local_dt( $rota_dt )->ymd;

   for my $key (grep { $_ =~ m{ \A $ymd _ }mx } sort keys %{ $data }) {
      my $slot_key = $data->{ $key }->key;
      my $scode = $data->{ $key }->operator;
      my $message = "action:impending-slot date:${dmy} days_in_advance:${days} "
                  . "shortcode:${scode} rota_date:${ymd} slot_key:${slot_key}";

      $self->send_event( $req, $message );
   }

   return OK;
}

sub restore_data : method {
   my $self = shift; my $conf = $self->config;

   my $path = $self->next_argv or throw Unspecified, [ 'file name' ];

   $path = io $path; $path->exists or throw PathNotFound, [ $path ];

   ensure_class_loaded 'Archive::Tar'; my $arc = Archive::Tar->new;

   chdir $conf->appldir; $arc->read( $path->pathname ); $arc->extract();

   my (undef, $date) = split m{ - }mx, $path->basename( '.tgz' ), 2;
   my $bdir = $conf->vardir->catdir( 'backups' );
   my $sql  = $conf->tempdir->catfile( $conf->database."-${date}.sql" );

   if ($sql->exists and lc $self->driver eq 'mysql') {
      $self->run_cmd
         ( [ 'mysql', '--host', $self->host,
             '--password='.$self->admin_password, '--user',
             $self->db_admin_ids->{mysql}, $self->database ],
           { in => $sql } );
      $sql->unlink;
   }

   return OK;
}

sub send_message : method {
   my $self       = shift;
   my $conf       = $self->config;
   my $opts       = $self->options;
   my $sink       = $self->next_argv or throw Unspecified, [ 'message sink' ];
   my $plate_name = $self->next_argv or throw Unspecified, [ 'template name' ];
   my $quote      = $self->next_argv ? TRUE : $opts->{quote} ? TRUE : FALSE;

   my ($stash, $template) = $opts->{stash}
                          ? $self->$_load_stash( $plate_name, $quote )
                          : $self->$_load_template( $plate_name, $quote );

   my $attaches = $self->$_qualify_assets( delete $stash->{attachments} );
   my $tuples   = $opts->{stash}      ? $self->$_load_from_stash( $stash )
                : $opts->{event}      ? $self->$_list_participents
                : $opts->{recipients} ? $self->$_list_recipients
                                      : $self->$_list_people;

   if ($sink eq 'email') {
      for my $person (map { $_->[ 1 ] } @{ $tuples }) {
         $self->$_send_email( $stash, $template, $person, $attaches );
      }
   }
   else { $self->$_send_sms( $stash, $template, $tuples ) }

   $conf->sessdir eq substr $plate_name, 0, length $conf->sessdir
      and unlink $plate_name;

   return OK;
}

sub upgrade_schema : method {
   my $self = shift;

   $self->preversion or throw Unspecified, [ 'preversion' ];
   $self->create_ddl;

   my $passwd = $self->password;
   my $class  = $self->schema_class;
   my $attr   = $self->$_connect_attr;
   my $schema = $class->connect( $self->dsn, $self->user, $passwd, $attr );

   $schema->storage->ensure_connected;
   $schema->upgrade_directory( $self->config->sharedir );
   $schema->upgrade;
   return OK;
}

sub vacant_slot : method {
   my $self = shift;
   my $scheme = $self->next_argv // 'https';
   my $hostport = $self->next_argv // 'localhost:5000';
   my $days = $self->next_argv // 7;
   my $rota_name = $self->next_argv // 'main';
   my $rota_dt = now_dt->add( days => $days );
   my $data = $self->$_assigned_slots( $rota_name, $rota_dt );
   my $req = $self->$_new_request( $scheme, $hostport );
   my $limits = $self->config->slot_limits;
   my $dmy = local_dt( $rota_dt )->dmy( '/' );
   my $ymd = local_dt( $rota_dt )->ymd;

   for my $slot_type (@{ SLOT_TYPE_ENUM() }) {
      my $wanted = $_slots_wanted->( $limits, $rota_dt, $slot_type );
      my $slots_claimed = grep { $_ =~ m{ _ $slot_type _ }mx }
                          grep { $_ =~ m{ \A $ymd _ }mx } keys %{ $data };
      my $message = "action:vacant-slot date:${dmy} days_in_advance:${days} "
                  . "rota_date:${ymd} slot_type:${slot_type}";

      $slots_claimed >= $wanted or $self->send_event( $req, $message );
   }

   return OK;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head2 C<backup_data> - Creates a backup of the database and documents

=head2 C<create_ddl> - Dump the database schema definition

Creates the DDL for multiple RDBMs

=head2 C<dump_connect_attr> - Displays database connection information

=head2 C<deploy_and_populate> - Create tables and populates them with initial data

=head2 C<geolocation> - Lookup geolocation information

=head2 C<impending_slot> - Generates the impending slots email

   bin/notitia-schema -q impending-slot [scheme] [hostport]

Run this from cron(8) to periodically trigger the impending slots email

=head2 C<send_message> - Send email or SMS to people

=head2 C<restore_data> - Restore a backup of the database and documents

=head2 C<upgrade_schema> - Upgrade the database schema

=head2 C<vacant_slot> - Generates the vacant slots email

   bin/notitia-schema -q vacant-slot [scheme] [hostport]

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
