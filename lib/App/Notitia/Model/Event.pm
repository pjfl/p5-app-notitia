package App::Notitia::Model::Event;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::Util      qw( bind bind_fields button check_field_js
                                create_link delete_button display_duration loc
                                management_link operation_links page_link_set
                                register_action_paths save_button
                                to_dt uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_member throw );
use Class::Usul::Time       qw( time2str );
use DateTime;
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(App::Notitia::Role::Messaging);

# Public attributes
has '+moniker' => default => 'event';

register_action_paths
   'event/event'         => 'event',
   'event/event_info'    => 'event-info',
   'event/event_summary' => 'event-summary',
   'event/events'        => 'events',
   'event/message'       => 'message-participents',
   'event/participate'   => 'participate',
   'event/participents'  => 'participents',
   'event/vehicle_event' => 'vehicle-event',
   'event/vehicle_info'  => 'vehicle-event-info';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav }->{list    }   = $self->admin_navigation_links( $req );
   $stash->{page}->{location} //= 'admin';

   return $stash;
};

# Private class attributes
my $_links_cache = {};

# Private functions
my $_bind_event_date = sub {
   my ($date, $disabled) = @_;

   return bind 'event_date', $date, { class    => 'standard-field required',
                                      disabled => $disabled };
};

my $_events_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "events_heading_${_}" ) } } 0 .. 4 ];
};

my $_event_links = sub {
   my ($self, $req, $event) = @_; my $uri = $event->uri;

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

my $_event_operation_links = sub {
   my ($req, $actionp, $uri) = @_;

   my $add_ev = create_link $req, $actionp, 'event',
                            { container_class => 'add-link' };
   my $vreq   = management_link $req, 'asset/request_vehicle', $uri;

   return operation_links [ $vreq, $add_ev ];
};

my $_participate_button = sub {
   my ($req, $name, $opts) = @_; $opts //= {};

   my $class  = 'save-button right-last';
   my $action = $opts->{cancel} ? 'unparticipate' : 'participate';

   return button $req, { class => $class }, $action, 'event', [ $name ];
};

my $_participent_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "participents_heading_${_}" ) } }
            0 .. 2 ];
};

my $_vehicle_events_uri = sub {
   my ($req, $vrn) = @_; my $after = DateTime->now->subtract( days => 1 )->ymd;

   return uri_for_action $req, 'asset/vehicle_events', [ $vrn ],
                         after => $after, service => TRUE;
};

my $_events_op_links = sub {
   my ($req, $moniker, $params, $pager) = @_;

   my $actionp    = "${moniker}/events";
   my $page_links = page_link_set $req, $actionp, [], $params, $pager;
   my $links      = [ create_link $req, "${moniker}/event", 'event' ];

   $page_links and unshift @{ $links }, $page_links;

   return operation_links $links;
};

# Private methods
my $_add_event_js = sub {
   my $self = shift; my $opts = { domain => 'schedule', form => 'Event' };

   return [ check_field_js( 'description', $opts ),
            check_field_js( 'name', $opts ) ];
};

my $_bind_event_fields = sub {
   my ($self, $event, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;
   my $editing  = $disabled ? $disabled : $event->uri ? TRUE : FALSE;
   my $map      = {
      description => { class    => 'standard-field autosize server',
                       disabled => $disabled },
      end_time    => { class    => 'standard-field', disabled => $disabled },
      name        => { class    => 'standard-field server',
                       disabled => $editing,
                       label    => 'event_name' },
      notes       => { class    => 'standard-field autosize',
                       disabled => $disabled },
      start_time  => { class    => 'standard-field', disabled => $disabled },
   };

   return bind_fields $self->schema, $event, $map, 'Event';
};

my $_format_as_markdown = sub {
   my ($self, $req, $event) = @_;

   my $name    = $event->name;
   my $date    = $event->start_date->clone->set_time_zone( 'local' );
   my $created = time2str '%Y-%m-%d %H:%M:%S %z', time, 'GMT';
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
   my ($self, $event, $disabled) = @_; my $schema = $self->schema;

   my $opts   = { fields => { selected => $event->owner } };
   my $people = $schema->resultset( 'Person' )->list_all_people( $opts );

   $opts = { class => 'standard-field required', numify => TRUE };

   $disabled and $opts->{disabled} = TRUE;

   return bind( 'owner', [ [ NUL, NUL ], @{ $people } ], $opts );
};

my $_participent_links = sub {
   my ($self, $req, $tuple, $event) = @_; my $name = $tuple->[ 1 ]->shortcode;

   my $links = $_links_cache->{ $name }; $links and return @{ $links };

   $links = [];

   push @{ $links },
         { value => management_link( $req, 'person/person_summary', $name ) };
   push @{ $links },
         { value => management_link( $req, 'event/event', 'unparticipate',
                       { args => [ $event->uri ], type => 'form_button' } ) };

   $_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_participent_ops_links = sub {
   my ($self, $req, $page, $params) = @_;

   $params->{name} = 'message_participents';

   my $actionp      = $self->moniker.'/message';
   my $message_link = $self->message_link( $req, $page, $actionp, $params );

   return operation_links [ $message_link ];
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

my $_update_event_post = sub {
   my ($self, $req, $file, $event) = @_;

   my $posts_model = $self->components->{posts};
   my $dir         = $posts_model->localised_posts_dir( $req->locale );
   my $path        = $dir->catfile( 'events', "${file}.md" );

   if ($event) {
      my $markdown = $self->$_format_as_markdown( $req, $event );

      $path->assert_filepath->println( $markdown );
      $posts_model->invalidate_docs_cache( $path->stat->{mtime} );
   }
   else {
      $path->exists and $path->unlink;
      $posts_model->invalidate_docs_cache( time );
   }

   return;
};

my $_create_event_post = sub {
   return shift->$_update_event_post( @_ );
};

my $_create_event = sub {
   my ($self, $req, $start_date, $event_type, $owner, $vrn) = @_;

   my $attr  = { rota       => 'main', # TODO: Naughty
                 start_date => $start_date,
                 event_type => $event_type,
                 owner      => $owner, };

   $vrn and $attr->{vehicle} = $vrn;

   my $event = $self->schema->resultset( 'Event' )->new_result( $attr );

   $self->$_update_event_from_request( $req, $event );

   try   { $event->insert }
   catch {
      $self->rethrow_exception
         ( $_, 'create', 'event', $event->name.SPC.$start_date->dmy( '/' ) );
   };

   return $event;
};

my $_delete_event_post = sub {
   return shift->$_update_event_post( @_ );
};

my $_delete_event = sub {
   my ($self, $uri) = @_;

   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );

   try   { $event->delete }
   catch { $self->rethrow_exception( $_, 'delete', 'event', $event->name ) };

   return $event;
};

my $_update_event = sub {
   my ($self, $req, $uri) = @_;

   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );

   $self->$_update_event_from_request( $req, $event );

   try   { $event->update }
   catch { $self->rethrow_exception( $_, 'update', 'event', $event->name ) };

   return $event;
};

# Public methods
sub create_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $date  = to_dt $req->body_params->( 'event_date' );
   my $event = $self->$_create_event( $req, $date, 'person', $req->username );

   $self->$_create_event_post( $req, $event->post_filename, $event );

   my $actionp  = $self->moniker.'/event';
   my $location = uri_for_action $req, $actionp, [ $event->uri ];
   my $message  =
      [ 'Event [_1] created by [_2]', $event->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub create_vehicle_event_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->uri_params->( 0 );
   my $date     = to_dt $req->body_params->( 'event_date' );
   my $event    = $self->$_create_event
                ( $req, $date, 'vehicle', $req->username, $vrn );
   my $location = $_vehicle_events_uri->( $req, $vrn );
   my $message  =
      [ 'Vehicle event [_1] created by [_2]', $event->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $uri   = $req->uri_params->( 0 );
   my $event = $self->$_delete_event( $uri );

   $self->$_delete_event_post( $req, $event->post_filename );

   my $location = uri_for_action $req, $self->moniker.'/events';
   my $message  = [ 'Event [_1] deleted by [_2]', $uri, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_vehicle_event_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->uri_params->( 0 );
   my $uri      = $req->uri_params->( 1 );
   my $event    = $self->$_delete_event( $uri );
   my $location = $_vehicle_events_uri->( $req, $vrn );
   my $message  =
      [ 'Vehicle event [_1] deleted by [_2]', $event->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub event : Role(event_manager) {
   my ($self, $req) = @_;

   my $uri        =  $req->uri_params->( 0, { optional => TRUE } );
   my $date       =  $req->query_params->( 'date', { optional => TRUE } );
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
      $fields->{date  } = $_bind_event_date->( $event->start_date, TRUE );
      $fields->{delete} = delete_button $req, $uri, { type => 'event' };
      $fields->{href  } = uri_for_action $req, $actionp, [ $uri ];
      $fields->{links } = $_event_operation_links->( $req, $actionp, $uri );
      $fields->{owner } = $self->$_owner_list( $event );
   }
   else {
      $date = $date ? to_dt( $date, 'GMT' )->dmy( '/' ) : time2str '%d/%m/%Y';
      $fields->{date  } = $_bind_event_date->( $date );
   }

   $fields->{save} = save_button $req, $uri, { type => 'event' };

   return $self->get_stash( $req, $page );
}

sub event_info : Role(any) {
   my ($self, $req) = @_;

   my $uri = $req->uri_params->( 0 );
   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $stash = $self->dialog_stash( $req, 'event-info' );
   my $fields = $stash->{page}->{fields};

   $fields->{owner} = $event->owner->label;
   $event->owner->postcode
      and $fields->{owner} .= ' ('.$event->owner->outer_postcode.')';
   ($fields->{start}, $fields->{end}) = display_duration $req, $event;

   return $stash;
}

sub event_summary : Role(any) {
   my ($self, $req) = @_;

   my $schema  =  $self->schema;
   my $user    =  $req->username;
   my $uri     =  $req->uri_params->( 0 );
   my $event   =  $schema->resultset( 'Event' )->find_event_by( $uri );
   my $person  =  $schema->resultset( 'Person' )->find_by_shortcode( $user );
   my $opts    =  { disabled => TRUE };
   my $page    =  {
      fields   => $self->$_bind_event_fields( $event, $opts ),
      template => [ 'contents', 'event' ],
      title    => loc( $req, 'event_summary_heading' ), };
   my $fields  =  $page->{fields};
   my $actionp =  $self->moniker.'/event';

   $fields->{date } = $_bind_event_date->( $event->start_date, TRUE );
   $fields->{href } = uri_for_action $req, $actionp, [ $uri ];
   $fields->{links} = $_event_operation_links->( $req, $actionp, $uri );
   $fields->{owner} = $self->$_owner_list( $event, TRUE );
   $opts = $person->is_participent_of( $uri ) ? { cancel => TRUE } : {};
   $fields->{participate} = $_participate_button->( $req, $uri, $opts );
   delete $fields->{notes};

   return $self->get_stash( $req, $page );
}

sub events : Role(any) {
   my ($self, $req) = @_;

   my $moniker   =  $self->moniker;
   my $params    =  $req->query_params->( { optional => TRUE } );
   my $after     =  $params->{after} ? to_dt( $params->{after} ) : FALSE;
   my $before    =  $params->{before} ? to_dt( $params->{before} ) : FALSE;
   my $opts      =  { after      => $after,
                      before     => $before,
                      event_type => 'person',
                      page       => $params->{page} // 1,
                      rows       => $req->session->rows_per_page };
   my $event_rs  =  $self->schema->resultset( 'Event' );
   my $events    =  $event_rs->search_for_events( $opts );
   my $pager     =  $events->pager;
   my $title     =  $after  ? 'current_events_heading'
                 :  $before ? 'previous_events_heading'
                 :            'events_management_heading';
   my $page      =  {
      fields     => {
         headers => $_events_headers->( $req ),
         links   => $_events_op_links->( $req, $moniker, $params, $pager ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, $title ), };
   my $rows      =  $page->{fields}->{rows};

   for my $event ($events->all) {
      push @{ $rows },
         [  { value => $event->label }, $self->$_event_links( $req, $event ) ];
   }

   return $self->get_stash( $req, $page );
}

sub message : Role(event_manager) {
   my ($self, $req) = @_;

   my $opts = { action => 'message-participents', layout => 'message-people' };

   return $self->message_stash( $req, $opts );
}

sub message_create_action : Role(event_manager) {
   return $_[ 0 ]->message_create( $_[ 1 ], { action => 'events' } );
}

sub participate_event_action : Role(any) {
   my ($self, $req) = @_;

   my $uri       = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_by_shortcode( $req->username );

   $person->add_participent_for( $uri );

   my $actionp   = $self->moniker.'/event_summary';
   my $location  = uri_for_action $req, $actionp, [ $uri ];
   my $message   = [ 'Event [_1] attendee [_2]', $uri, $person->label ];

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
   my $opts      =  { event => $uri };
   my $fields    =  $page->{fields};
   my $rows      =  $fields->{rows};

   $fields->{links} = $self->$_participent_ops_links( $req, $page, $opts );

   for my $tuple (@{ $person_rs->list_participents( $event ) }) {
      push @{ $rows },
         [ { value => $tuple->[ 0 ] },
           $self->$_participent_links( $req, $tuple, $event ) ];
   }

   return $self->get_stash( $req, $page );
}

sub unparticipate_event_action : Role(any) {
   my ($self, $req) = @_;

   my $user      = $req->username;
   my $uri       = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_by_shortcode( $user );

   $person->delete_participent_for( $uri );

   my $actionp   = $self->moniker.'/event_summary';
   my $location  = uri_for_action $req, $actionp, [ $uri ];
   my $message   = [ 'Event [_1] attendence cancelled for [_2]',
                     $uri, $person->label ];

   return { redirect => { location => $location, message => $message } };
}

sub update_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $uri   = $req->uri_params->( 0 );
   my $event = $self->$_update_event( $req, $uri );

   $self->$_update_event_post( $req, $event->post_filename, $event );

   my $actionp  = $self->moniker.'/event';
   my $location = uri_for_action $req, $actionp, [ $uri ];
   my $message  = [ 'Event [_1] updated by [_2]', $uri, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub update_vehicle_event_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->uri_params->( 0 );
   my $uri      = $req->uri_params->( 1 );
   my $event    = $self->$_update_event( $req, $uri );
   my $location = $_vehicle_events_uri->( $req, $vrn );
   my $message  =
      [ 'Vehicle event [_1] updated by [_2]', $event->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
};

sub vehicle_event : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn        =  $req->uri_params->( 0, { optional => TRUE } );
   my $uri        =  $req->uri_params->( 1, { optional => TRUE } );
   my $event      =  $self->$_maybe_find_event( $uri );
   my $page       =  {
      fields      => $self->$_bind_event_fields( $event ),
      first_field => 'name',
      literal_js  => $self->$_add_event_js(),
      template    => [ 'contents', 'event' ],
      title       => loc( $req, $uri ? 'vehicle_event_edit_heading'
                                     : 'vehicle_event_create_heading' ), };
   my $actionp    =  $self->moniker.'/vehicle_event';
   my $fields     =  $page->{fields};

   if ($uri) {
      $fields->{date  } = $_bind_event_date->( $event->start_date, TRUE );
      $fields->{delete} = delete_button $req, $uri, { type => 'vehicle_event' };
      $fields->{href  } = uri_for_action $req, $actionp, [ $vrn, $uri ];
   }
   else {
      $fields->{date} = $_bind_event_date->( time2str( '%d/%m/%Y' ) );
      $fields->{href} = uri_for_action $req, $actionp, [ $vrn ];
   }

   $fields->{owner  } = $self->$_owner_list( $event );
   $fields->{save   } = save_button $req, $uri, { type => 'vehicle_event' };
   $fields->{vehicle} = bind 'vehicle', $uri ? $event->vehicle->label : $vrn,
                             { disabled => TRUE };

   return $self->get_stash( $req, $page );
}

sub vehicle_info : Role(rota_manager) {
   my ($self, $req) = @_;

   my $uri = $req->uri_params->( 0 );
   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $stash = $self->dialog_stash( $req, 'vehicle-event-info' );
   my $fields = $stash->{page}->{fields};

   $fields->{owner} = $event->owner->label;
   $event->owner->postcode
      and $fields->{owner} .= ' ('.$event->owner->outer_postcode.')';
   ($fields->{start}, $fields->{end}) = display_duration $req, $event;

   return $stash;
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
