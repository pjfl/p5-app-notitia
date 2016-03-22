package App::Notitia::Model::Event;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind bind_fields button
                                check_field_server create_link
                                delete_button loc
                                management_link register_action_paths
                                save_button uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_member throw );
use Class::Usul::Time       qw( str2date_time time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'event';

register_action_paths
   'event/event'         => 'event',
   'event/events'        => 'events',
   'event/participate'   => 'participate',
   'event/participents'  => 'participents',
   'event/event_summary' => 'event-summary';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;
   $stash->{page}->{location} //= 'admin';

   return $stash;
};

# Private class attributes
my $_links_cache = {};

# Private functions
my $_events_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "events_heading_${_}" ) } } 0 .. 4 ];
};

my $_event_links = sub {
   my ($self, $req, $event) = @_; my $uri = $event->[ 1 ]->uri;

   my $links = $_links_cache->{ $uri }; $links and return @{ $links };

   my @actions = qw( event/event event/participents
                     asset/request_vehicle event/event_summary );

   $links = [];

   for my $actionp (@actions) {
      push @{ $links }, { value => management_link( $req, $actionp, $uri ) };
   }

   $_links_cache->{ $uri } = $links;

   return @{ $links };
};

my $_participate_button = sub {
   my ($req, $name, $opts) = @_; $opts //= {};

   my $action = $opts->{cancel} ? 'unparticipate' : 'participate';

   return button $req, { class => 'right-last' }, $action, 'event', [ $name ];
};

my $_participent_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "participents_heading_${_}" ) } }
            0 .. 2 ];
};

# Private methods
my $_add_event_js = sub {
   my $self = shift; my $opts = { domain => 'schedule', form => 'Event' };

   return [ check_field_server( 'description', $opts ),
            check_field_server( 'name', $opts ) ];
};

my $_bind_event_fields = sub {
   my ($self, $event, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;
   my $map      = {
      description => { class    => 'standard-field autosize server',
                       disabled => $disabled },
      end_time    => { disabled => $disabled },
      name        => { class    => 'standard-field server',
                       disabled => $disabled,
                       label    => 'event_name' },
      notes       => { class    => 'standard-field autosize',
                       disabled => $disabled },
      start_time  => { disabled => $disabled},
   };

   return bind_fields $self->schema, $event, $map, 'Event';
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
               . "created: ${created}\nrole: anon\ntitle: ${name}\n---\n";
   my $desc    = $event->description."\n\n";
   my $opts    = { params => [ $date->dmy( '/' ),
                               $event->start_time, $event->end_time ],
                   no_quote_bind_values => TRUE };
   my $when    = loc( $req, 'event_blog_when', $opts )."\n\n";
   my $actionp = $self->moniker.'/event_summary';
   my $href    = uri_for_action $req, $actionp, [ $event->uri ];
      $opts    = { params => [ $href ], no_quote_bind_values => TRUE };
   my $link    = loc( $req, 'event_blog_link', $opts )."\n\n";

   return $yaml.$desc.$when.$link;
};

my $_maybe_find_event = sub {
   my ($self, $uri) = @_; $uri or return Class::Null->new;

   my $schema = $self->schema; my $opts = { prefetch => [ 'owner' ] };

   return $schema->resultset( 'Event' )->find_event_by( $uri, $opts );
};

my $_owner_list = sub {
   my ($self, $event) = @_; my $schema = $self->schema;

   my $opts   = { fields => { selected => $event->owner } };
   my $people = $schema->resultset( 'Person' )->list_all_people( $opts );

   return bind( 'owner', [ [ NUL, NUL ], @{ $people } ], { numify => TRUE } );
};

my $_participent_links = sub {
   my ($self, $req, $person, $event) = @_; my $name = $person->[ 1 ]->name;

   my $links = $_links_cache->{$name }; $links and return @{ $links };

   $links = [];

   push @{ $links },
         { value => management_link( $req, 'admin/person_summary', $name ) };
   push @{ $links },
         { value => management_link( $req, 'event/event', 'unparticipate',
                       { args => [ $event->uri ], type => 'form_button' } ) };

   $_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_update_event_from_request = sub {
   my ($self, $req, $event) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( description end_time name notes start_time )) {
      if (is_member $attr, [ 'description', 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      $event->$attr( $v );
   }

   my $v = $params->( 'owner', $opts ); defined $v and $event->owner_id( $v );

   return;
};

my $_write_blog_post = sub {
   my ($self, $req, $event, $date) = @_;

   my $posts_model = $self->components->{posts};
   my $dir         = $posts_model->localised_posts_dir( $req->locale );
   my $file        = $date.'_'.$event->uri;
   my $path        = $dir->catfile( 'events', $file.'.md' );
   my $markdown    = $self->$_format_as_markdown( $req, $event );

   $path->assert_filepath->println( $markdown );
   $posts_model->invalidate_docs_cache( $path->stat->{mtime} );

   return;
};

# Public methods
sub create_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $date     =  str2date_time $req->body_params->( 'event_date' ), 'GMT';
   my $event    =  $self->schema->resultset( 'Event' )->new_result
      ( { rota  => 'main', # TODO: Naughty
          date  => $date->ymd,
          owner => $req->username, } );

   $self->$_update_event_from_request( $req, $event ); $event->insert;
   $self->$_write_blog_post( $req, $event, $date->ymd );

   my $actionp  = $self->moniker.'/event';
   my $location = uri_for_action $req, $actionp, [ $event->uri ];
   my $message  =
      [ 'Event [_1] created by [_2]', $event->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $uri   = $req->uri_params->( 0 );
   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );

   $event->delete;

   my $location = uri_for_action $req, $self->moniker.'/events';
   my $message  = [ 'Event [_1] deleted by [_2]', $uri, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub event : Role(event_manager) {
   my ($self, $req) = @_;

   my $uri        =  $req->uri_params->( 0, { optional => TRUE } );
   my $event      =  $self->$_maybe_find_event( $uri );
   my $page       =  {
      fields      => $self->$_bind_event_fields( $event ),
      first_field => 'name',
      literal_js  => $self->$_add_event_js(),
      template    => [ 'contents', 'event' ],
      title       => loc( $req, $uri ? 'event_edit_heading'
                                     : 'event_create_heading' ), };
   my $fields     =  $page->{fields};
   my $actionp    =  $self->moniker.'/event';

   if ($uri) {
      $fields->{date  } = bind 'event_date', $event->rota->date,
                          { disabled => TRUE };
      $fields->{delete} = delete_button $req, $uri, 'event';
      $fields->{href  } = uri_for_action $req, $actionp, [ $uri ];
      $fields->{owner } = $self->$_owner_list( $event );
   }
   else { $fields->{date} = bind 'event_date', time2str '%d/%m/%Y' }

   $fields->{save} = save_button $req, $uri, 'event';

   return $self->get_stash( $req, $page );
}

sub event_summary : Role(any) {
   my ($self, $req) = @_;

   my $schema  =  $self->schema;
   my $user    =  $req->username;
   my $uri     =  $req->uri_params->( 0 );
   my $event   =  $schema->resultset( 'Event' )->find_event_by( $uri );
   my $person  =  $schema->resultset( 'Person' )->find_person_by( $user );
   my $opts    =  { disabled => TRUE };
   my $page    =  {
      fields   => $self->$_bind_event_fields( $event, $opts ),
      template => [ 'contents', 'event' ],
      title    => loc( $req, 'event_summary_heading' ), };
   my $fields  =  $page->{fields};
   my $actionp =  $self->moniker.'/event';

   $fields->{add } = create_link $req, $actionp, 'event',
                        { container_class => 'right' };
   $fields->{date} = bind 'event_date', $event->rota->date, $opts;
   $fields->{href} = uri_for_action $req, $actionp, [ $uri ];
   $opts = $person->is_participent_of( $uri ) ? { cancel => TRUE } : {};
   $fields->{participate} = $_participate_button->( $req, $uri, $opts );
   delete $fields->{notes};

   return $self->get_stash( $req, $page );
}

sub events : Role(any) {
   my ($self, $req) = @_;

   my $actionp   =  $self->moniker.'/event';
   my $page      =  {
      fields     => {
         add     => create_link( $req, $actionp, 'event' ),
         headers => $_events_headers->( $req ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, 'events_management_heading' ), };
   my $event_rs  =  $self->schema->resultset( 'Event' );
   my $rows      =  $page->{fields}->{rows};
   my $params    =  $req->query_params;
   my $opts      =  { after  => $params->( 'after',  { optional => TRUE } ),
                      before => $params->( 'before', { optional => TRUE } ), };

   for my $event (@{ $event_rs->list_all_events( $opts ) }) {
      push @{ $rows },
         [  { value => $event->[ 0 ] }, $self->$_event_links( $req, $event ) ];
   }

   return $self->get_stash( $req, $page );
}

sub participate_event_action : Role(any) {
   my ($self, $req) = @_;

   my $uri       = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $req->username );

   $person->add_participent_for( $uri );

   my $actionp   = $self->moniker.'/event_summary';
   my $location  = uri_for_action $req, $actionp, [ $uri ];
   my $message   = [ 'Event [_1] attendee [_2]', $uri, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub participents : Role(any) {
   my ($self, $req) = @_;

   my $uri       =  $req->uri_params->( 0 );
   my $event     =  $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $page      =  {
      fields     => {
         headers => $_participent_headers->( $req ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, 'participents_management_heading',
                         { params => [ $event->name ],
                           no_quote_bind_values => TRUE } ) };
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $rows      =  $page->{fields}->{rows};

   for my $person (@{ $person_rs->list_participents( $event ) }) {
      push @{ $rows },
         [ { value => $person->[ 0 ] },
           $self->$_participent_links( $req, $person, $event ) ];
   }

   return $self->get_stash( $req, $page );
}

sub unparticipate_event_action : Role(any) {
   my ($self, $req) = @_;

   my $user      = $req->username;
   my $uri       = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $user );

   $person->delete_participent_for( $uri );

   my $actionp   = $self->moniker.'/event_summary';
   my $location  = uri_for_action $req, $actionp, [ $uri ];
   my $message   = [ 'Event [_1] attendence cancelled for [_2]', $uri, $user ];

   return { redirect => { location => $location, message => $message } };
}

sub update_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $uri   = $req->uri_params->( 0 );
   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );

   $self->$_update_event_from_request( $req, $event ); $event->update;
   $self->$_write_blog_post( $req, $event, $event->rota->date->ymd );

   my $actionp  = $self->moniker.'/event';
   my $location = uri_for_action $req, $actionp, [ $uri ];
   my $message  = [ 'Event [_1] updated by [_2]', $uri, $req->username ];

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
