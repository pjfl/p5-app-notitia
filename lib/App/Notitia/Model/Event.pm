package App::Notitia::Model::Event;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TILDE TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind create_button
                                delete_button field_options loc
                                management_button register_action_paths
                                save_button uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_member throw );
use Class::Usul::Time       qw( time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'event';

register_action_paths
   'event/event'        => 'event',
   'event/events'       => 'events',
   'event/participate'  => 'participate',
   'event/participents' => 'participents',
   'event/summary'      => 'event-summary';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Private class attributes
my $_event_links_cache = {};

# Private functions
my $_events_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "events_heading_${_}" ) } } 0 .. 3 ];
};

my $_participate_button = sub {
   my ($req, $name, $opts) = @_; $opts //= {};

   my $k      = $opts->{cancel} ? 'unparticipate' : 'participate';
   my $button = { container_class => 'right', label => $k,
                  value           => "${k}_event" };

   $button->{tip} = loc( $req, 'Hint' ).SPC.TILDE.SPC
                  . loc( $req, "${k}_tip", [ $name ] );

   return $button;
};

my $_participent_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "participents_heading_${_}" ) } }
            0 .. 1 ];
};

# Private methods
my $_add_event_js = sub {
   my $self = shift; my $opts = { domain => 'schedule', form => 'Event' };

   return [ $self->check_field_server( 'description', $opts ),
            $self->check_field_server( 'name', $opts ) ];
};

my $_bind_event_fields = sub {
   my ($self, $event, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;
   my $map      = {
      description => { class    => 'autosize server', disabled => $disabled },
      end_time    => { disabled => $disabled },
      name        => { class    => 'server', disabled => $disabled,
                       label    => 'event_name' },
      notes       => { class    => 'autosize', disabled => $disabled },
      start_time  => { disabled => $disabled},
   };

   return $self->bind_fields( $event, $map, 'Event' );
};

my $_event_links = sub {
   my ($self, $req, $event) = @_;

   my $name = $event->[ 1 ]->name; my $date = $event->[ 1 ]->rota->date->ymd;

   my $links = $_event_links_cache->{ my $k = "${name}/${date}" };

   $links and return @{ $links }; $links = [];

   my $args = [ $name, $date ];

   for my $path ( qw( event/event event/participents event/summary ) ) {
      my ($moniker, $action) = split m{ / }mx, $path, 2;
      my $href = uri_for_action $req, $path, $args;

      push @{ $links }, {
         value => management_button( $req, $name, $action, $href ) };
   }

   $_event_links_cache->{ $k } = $links;

   return @{ $links };
};

my $_find_rota = sub {
   return $_[ 0 ]->schema->resultset( 'Rota' )->find_rota( $_[ 1 ], $_[ 2 ] );
};

my $_format_as_markdown = sub {
   my ($self, $req, $event) = @_;

   my $name    = $event->name;
   my $date    = $event->rota->date;
   my $created = time2str '%Y-%m-%d %H:%M:%S %z', time, 'UTC';
   my $yaml    = "---\nauthor: ".$event->owner."\n"
               . "created: ${created}\ntitle: ${name}\n---\n";
   my $desc    = $event->description."\n\n";
   my $opts    = { params => [ $date->dmy( '/' ),
                               $event->start_time, $event->end_time ],
                   no_quote_bind_values => TRUE };
   my $when    = loc( $req, 'event_blog_when', $opts )."\n\n";
   my $actionp = $self->moniker.'/summary';
   my $href    = uri_for_action $req, $actionp, [ $name, $date->ymd ];
      $opts    = { params => [ $href ], no_quote_bind_values => TRUE };
   my $link    = loc( $req, 'event_blog_link', $opts )."\n\n";

   return $yaml.$desc.$when.$link;
};

my $_maybe_find_event = sub {
   my ($self, $name, $date) = @_; $name or return Class::Null->new;

   my $schema = $self->schema; my $opts = { prefetch => [ 'owner' ] };

   return $schema->resultset( 'Event' )->find_event_by( $name, $date, $opts );
};

my $_participent_links = sub {
   my ($self, $req, $person) = @_; my $name = $person->[ 1 ]->name;

   my $links = $_event_links_cache->{$name };

   $links and return @{ $links }; $links = [];

   for my $path ( qw( admin/summary ) ) {
      my ($moniker, $action) = split m{ / }mx, $path, 2;
      my $href = uri_for_action $req, $path, [ $name ];

      push @{ $links }, {
         value => management_button( $req, $name, $action, $href ) };
   }

   $_event_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_select_owner_list = sub {
   my ($self, $event) = @_; my $schema = $self->schema;

   my $opts   = { fields => { selected => $event->owner } };
   my $people = $schema->resultset( 'Person' )->list_all_people( $opts );

   return bind( 'owner', [ [ NUL, NUL ], @{ $people } ], { numify => TRUE } );
};

my $_update_event_from_request = sub {
   my ($self, $req, $event) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   for my $attr (qw( description end_time name notes start_time )) {
      if (is_member $attr, [ 'description', 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      is_member $attr, [ 'end_time', 'start_time' ]
          and $v =~ s{ \A (\d\d) (\d\d) \z }{$1:$2}mx;

      $event->$attr( $v );
   }

   my $v = $params->( 'owner', $opts ); defined $v and $event->owner_id( $v );

   return;
};

my $_write_blog_post = sub {
   my ($self, $req, $event, $date) = @_;

   my $posts_model = $self->components->{posts};
   my $dir         = $posts_model->localised_posts_dir( $req->locale );
   my $file        = $date.'_'.(lc $event->name);
   my $token       = lc substr create_token( $file ), 0, 6;

   $file =~ s{ [ ] }{-}gmx; $file .= "-${token}";

   my $path        = $dir->catfile( 'events', $file.'.md' );
   my $markdown    = $self->$_format_as_markdown( $req, $event );

   $path->assert_filepath->println( $markdown );
   $posts_model->invalidate_docs_cache( $path->stat->{mtime} );

   return;
};

# Public methods
sub create_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $date     =  $req->body_params->( 'event_date' );
   my $event    =  $self->schema->resultset( 'Event' )->new_result
      ( { rota  => 'main', # TODO: Naughty
          date  => $date,
          owner => $req->username, } );

   $self->$_update_event_from_request( $req, $event ); $event->insert;
   $self->$_write_blog_post( $req, $event, $date );

   my $actionp  = $self->moniker.'/event';
   my $location = uri_for_action $req, $actionp, [ $event->name, $date ];
   my $message  =
      [ 'Event [_1] created by [_2]', $event->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $name  = $req->uri_params->( 0 );
   my $date  = $req->uri_params->( 1 );
   my $rs    = $self->schema->resultset( 'Event' );
   my $event = $rs->find_event_by( $name, $date );

   $event->delete;

   my $location = uri_for_action $req, $self->moniker.'/events';
   my $message  = [ 'Event [_1] deleted by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub event : Role(event_manager) {
   my ($self, $req) = @_;

   # TODO: Fix the event name so that it's good for the href - no space or %
   my $name       =  $req->uri_params->( 0, { optional => TRUE } );
   my $date       =  $req->uri_params->( 1, { optional => TRUE } );
   my $event      =  $self->$_maybe_find_event( $name, $date );
   my $page       =  {
      fields      => $self->$_bind_event_fields( $event ),
      first_field => 'name',
      literal_js  => $self->$_add_event_js(),
      template    => [ 'contents', 'event' ],
      title       => loc( $req, 'event_management_heading' ), };
   my $fields     =  $page->{fields};
   my $actionp    =  $self->moniker.'/event';

   if ($name) {
      $fields->{date  } = bind 'event_date', $event->rota->date,
                          { disabled => TRUE };
      $fields->{delete} = delete_button $req, $name, 'event';
      $fields->{href  } = uri_for_action $req, $actionp, [ $name, $date ];
      $fields->{owner } = $self->$_select_owner_list( $event );
   }
   else { $fields->{date} = bind 'event_date', time2str '%Y-%m-%d' }

   $fields->{save} = save_button $req, $name, 'event';

   return $self->get_stash( $req, $page );
}

sub events : Role(any) {
   my ($self, $req) = @_;

   my $actionp   =  $self->moniker.'/event';
   my $page      =  {
      fields     => {
         add     => create_button( $req, $actionp, 'event' ),
         headers => $_events_headers->( $req ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, 'events_management_heading' ), };
   my $event_rs  =  $self->schema->resultset( 'Event' );
   my $rows      =  $page->{fields}->{rows};

   for my $event (@{ $event_rs->list_all_events( { order_by => 'date' } ) }) {
      push @{ $rows },
         [ { value => $event->[ 0 ] }, $self->$_event_links( $req, $event ) ];
   }

   return $self->get_stash( $req, $page );
}

sub participate_event_action : Role(any) {
   my ($self, $req) = @_;

   my $name      = $req->uri_params->( 0 );
   my $date      = $req->uri_params->( 1 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $req->username );

   $person->add_participent_for( $name, $date );

   my $actionp   = $self->moniker.'/summary';
   my $location  = uri_for_action $req, $actionp, [ $name, $date ];
   my $message   = [ 'Event [_1] attendee [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub participents : Role(event_manager) Role(person_manager) {
   my ($self, $req) = @_;

   my $name      =  $req->uri_params->( 0 );
   my $date      =  $req->uri_params->( 1 );
   my $page      =  {
      fields     => {
         headers => $_participent_headers->( $req ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, 'participents_management_heading' ), };
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $event_rs  =  $self->schema->resultset( 'Event' );
   my $event     =  $event_rs->find_event_by( $name, $date );
   my $rows      =  $page->{fields}->{rows};

   for my $person (@{ $person_rs->list_participents( $event ) }) {
      push @{ $rows },
         [ { value => $person->[ 0 ] },
           $self->$_participent_links( $req, $person ) ];
   }

   return $self->get_stash( $req, $page );
}

sub summary : Role(any) {
   my ($self, $req) = @_;

   my $schema  =  $self->schema;
   my $user    =  $req->username;
   my $name    =  $req->uri_params->( 0 );
   my $date    =  $req->uri_params->( 1 );
   my $event   =  $schema->resultset( 'Event' )->find_event_by( $name, $date );
   my $person  =  $schema->resultset( 'Person' )->find_person_by( $user );
   my $opts    =  { disabled => TRUE };
   my $page    =  {
      fields   => $self->$_bind_event_fields( $event, $opts ),
      template => [ 'contents', 'event' ],
      title    => loc( $req, 'event_summary_heading' ), };
   my $fields  =  $page->{fields};
   my $actionp =  $self->moniker.'/event';

   $fields->{date} = bind 'event_date', $event->rota->date, $opts;
   $fields->{href} = uri_for_action $req, $actionp, [ $name, $date ];
   $opts = $person->is_participent_of( $name, $date ) ? { cancel => TRUE } : {};
   $fields->{participate} = $_participate_button->( $req, $name, $opts );
   delete $fields->{notes};

   return $self->get_stash( $req, $page );
}

sub unparticipate_event_action : Role(any) {
   my ($self, $req) = @_;

   my $user      = $req->username;
   my $name      = $req->uri_params->( 0 );
   my $date      = $req->uri_params->( 1 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $user );

   $person->delete_participent_for( $name, $date );

   my $actionp   = $self->moniker.'/summary';
   my $location  = uri_for_action $req, $actionp, [ $name, $date ];
   my $message   = [ 'Event [_1] attendence cancelled for [_2]', $name, $user ];

   return { redirect => { location => $location, message => $message } };
}

sub update_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $name  = $req->uri_params->( 0 );
   my $date  = $req->uri_params->( 1 );
   my $rs    = $self->schema->resultset( 'Event' );
   my $event = $rs->find_event_by( $name, $date );

   $self->$_update_event_from_request( $req, $event );
   $event->rota_id( $self->$_find_rota( 'main', $date )->id ); # TODO: Naughty
   $event->update;
   $self->$_write_blog_post( $req, $event, $date );

   my $actionp  = $self->moniker.'/event';
   my $location = uri_for_action $req, $actionp, [ $name, $date ];
   my $message  = [ 'Event [_1] updated by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Event - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Event;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

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
