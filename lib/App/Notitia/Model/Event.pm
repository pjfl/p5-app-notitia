package App::Notitia::Model::Event;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_action p_button p_list
                                p_fields p_row p_table p_tag p_text
                                p_textfield );
use App::Notitia::Util      qw( check_field_js display_duration loc
                                locd locm make_tip management_link now_dt
                                page_link_set register_action_paths to_dt to_msg
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_member throw );
use Class::Usul::Time       qw( time2str );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(App::Notitia::Role::Messaging);

# Public attributes
has '+moniker' => default => 'event';

register_action_paths
   'event/event'          => 'event',
   'event/event_info'     => 'event-info',
   'event/event_summary'  => 'event-summary',
   'event/events'         => 'events',
   'event/message'        => 'message-participants',
   'event/participate'    => 'participate',
   'event/participents'   => 'participants',
   'event/training_event' => 'training-event',
   'event/vehicle_event'  => 'vehicle-event',
   'event/vehicle_info'   => 'vehicle-event-info';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_bind_date = sub {
   my ($req, $name, $date, $event, $opts) = @_;

   my $disabled = $opts->{disabled} || $event->uri ? TRUE : FALSE;
   my $dt = $event->uri ? $date : $opts->{date} ? to_dt $opts->{date} : now_dt;

   return { class => 'standard-field required', disabled => $disabled,
            label => $name, name => $name, type => 'date',
            value => locd( $req, $dt ) };
};

my $_bind_end_date = sub {
   return $_bind_date->
      ( $_[ 0 ], 'end_date', $_[ 1 ]->end_date, $_[ 1 ], $_[ 2 ] );
};

my $_bind_start_date = sub {
   return $_bind_date->
      ( $_[ 0 ], 'start_date', $_[ 1 ]->start_date, $_[ 1 ], $_[ 2 ] );
};

my $_create_action = sub {
   return { action => 'create', container_class => 'add-link',
            request => $_[ 0 ] };
};

my $_events_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "events_heading_${_}" ) } } 0 .. 4 ];
};

my $_event_ops_links = sub {
   my ($req, $actionp, $uri) = @_;

   my $href = uri_for_action $req, $actionp;
   my $add_event = f_link 'event', $href, $_create_action->( $req );
   my $vehicle_request = management_link $req, 'asset/request_vehicle', $uri;

   return [ $vehicle_request, $add_event ];
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

my $_add_participate_button = sub {
   my ($req, $form, $event, $person) = @_;

   my $uri     = $event->uri;
   my $action  = $person->is_participating_in( $uri, $event )
               ? 'unparticipate' : 'participate';
   my $t_opts  = { class => 'field-text right-last', label => NUL };

   my $text; $action eq 'participate'
      and $event->max_participents
      and $event->count_of_participents >= $event->max_participents
      and $text = locm $req, 'Maximum number of paticipants reached'
      and p_text $form, 'info', $text, $t_opts
      and return;

   if ($action eq 'participate' and $event->event_type eq 'training') {
      my $course; $person->is_enroled_on( $event->course_type )
         and $course = $person->assert_enroled_on( $event->course_type );

      not $course
         and $text = locm $req, 'Not enroled on this course'
         and p_text $form, 'info', $text, $t_opts
         and return;

      $course->status ne 'enroled'
         and $text = locm $req, 'Current course status: [_1]', $course->status
         and p_text $form, 'info', $text, $t_opts
         and return;
   }

   now_dt > $event->start_date
      and $text = locm $req, 'This event has already happened'
      and p_text $form, 'info', $text, $t_opts
      and return;

   p_button $form, "${action}_event", "${action}_event", {
      class => 'save-button', container_class => 'right-last',
      tip => make_tip( $req, "${action}_event_tip", [ $uri ] ) };

   return;
};

my $_participent_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "participents_heading_${_}" ) } }
            0 .. 2 ];
};

my $_participents_title = sub {
   my ($req, $event) = @_; my $label = $event->name;

   if ($event->event_type eq 'training') {
      $label = locm $req, lc $event->name;
   }

   return locm $req, 'participents_management_heading', $label;
};

my $_vehicle_events_uri = sub {
   my ($req, $vrn) = @_; my $after = now_dt->subtract( days => 1 )->ymd;

   return uri_for_action $req, 'asset/vehicle_events', [ $vrn ],
                         after => $after, service => TRUE;
};

my $_events_ops_links = sub {
   my ($req, $moniker, $params, $pager) = @_;

   my $actionp = "${moniker}/events";
   my $page_links = page_link_set $req, $actionp, [], $params, $pager;
   my $href = uri_for_action $req, "${moniker}/event";
   my $links = [ f_link 'event', $href, $_create_action->( $req ) ];

   $page_links and unshift @{ $links }, $page_links;

   return $links;
};

# Private methods
my $_add_event_js = sub {
   my $self = shift; my $opts = { domain => 'schedule', form => 'Event' };

   return [ check_field_js( 'description', $opts ),
            check_field_js( 'name', $opts ) ];
};

my $_bind_owner = sub {
   my ($self, $event, $disabled) = @_; $event->uri or return FALSE;

   my $rs = $self->schema->resultset( 'Person' );
   my $opts = { fields => { selected => $event->owner } };
   my $people = $rs->list_people( 'event_manager', $opts );

   return {
      class => 'standard-field required', disabled => $disabled, numify => TRUE,
      type  => 'select', value => [ [ NUL, undef ], @{ $people } ] };
};

my $_event_links = sub {
   my ($self, $req, $event) = @_; my $links = []; my $uri = $event->uri;

   my @actions = qw( event/event event/participents
                     asset/request_vehicle event/event_summary );

   for my $actionp (@actions) {
      push @{ $links }, { value => management_link( $req, $actionp, $uri, {
         params => $req->query_params->( { optional => TRUE } ) } ) };
   }

   return [ { value => $event->label }, @{ $links } ];
};

my $_format_as_markdown = sub {
   my ($self, $req, $event) = @_;

   my $name    = $event->name;
   my $date    = $event->start_date->clone->set_time_zone( 'local' );
   my $created = time2str '%Y-%m-%d %H:%M:%S %z', time, 'GMT';
   my $yaml    = "---\nauthor: ".$event->owner."\n"
               . "created: ${created}\nrole: any\ntitle: ${name}\n---\n";
   my $desc    = $event->description."\n\n";
   my @opts    = ($date->dmy( '/' ), $event->start_time, $event->end_time);
   my $when    = locm( $req, 'event_blog_when', @opts )."\n\n";
   my $actionp = $self->moniker.'/event_summary';
   my $href    = uri_for_action $req, $actionp, [ $event->uri ];
   my $link    = locm( $req, 'event_blog_link', $href )."\n\n";

   return $yaml.$desc.$when.$link;
};

my $_maybe_find_event = sub {
   my ($self, $uri) = @_; $uri or return Class::Null->new;

   my $schema = $self->schema; my $opts = { prefetch => [ 'owner' ] };

   return $schema->resultset( 'Event' )->find_event_by( $uri, $opts );
};

my $_unparticipate_allowed = sub {
   my ($req, $scode) = @_;

   $scode eq $req->username and return TRUE;
   is_member 'event_manager', $req->session->roles and return TRUE;
   is_member 'training_manager', $req->session->roles and return TRUE;
   return FALSE;
};

my $_participent_links = sub {
   my ($self, $req, $page, $event, $tuple) = @_;

   my $name = $tuple->[ 1 ]->shortcode; my $disabled = $page->{disabled};

   return
   [ { value => $tuple->[ 0 ] },
     { value => management_link( $req, 'person/person_summary', $name ) },
     { value => ($disabled or not $_unparticipate_allowed->( $req, $name ))
              ? locm $req, 'Unparticipate'
              : management_link( $req, 'event/event', 'unparticipate', {
                 args => [ $event->uri ], type => 'form_button' } ) }
     ];
};

my $_participent_ops_links = sub {
   my ($self, $req, $page, $params) = @_;

   my $name         = 'message_participents';
   my $actionp      = $self->moniker.'/message';
   my $href         = uri_for_action $req, $actionp, [], $params;
   my $message_link = $self->message_link( $req, $page, $href, $name );

   return [ $message_link ];
};

my $_update_event_from_request = sub {
   my ($self, $req, $event) = @_;

   my $params = $req->body_params; my $opts = { optional => TRUE };

   for my $attr (qw( description end_time max_participents
                     name notes start_time )) {
      if (is_member $attr, [ 'description', 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      $attr eq 'max_participents' and not $v and undef $v;

      $event->$attr( $v );
   }

   my $v = $params->( 'owner', $opts );

   defined $v and length $v and $event->owner_id( $v );
   $v = $params->( 'location', $opts );
   length $v or undef $v; $event->location_id( $v );

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

my $_bind_event_name = sub {
   my ($self, $event, $opts) = @_;

   my $disabled = $opts->{disabled} || ($event->uri ? TRUE : FALSE);

   if ($opts->{training_event}) {
      $opts = { fields => { selected => $event->course_type },
                type => 'course' };

      my $courses = $self->schema->resultset( 'Type' )->list_types( $opts );

      return { class => 'standard-field required', disabled => $disabled,
               label => 'training_event_name', type => 'select',
               value => [ [ NUL, undef ], @{ $courses } ] };
   }

   return { class    => 'standard-field server',
            disabled => $disabled, label => 'event_name' };
};

my $_bind_location = sub {
   my ($self, $event, $opts) = @_;

   my $disabled = $opts->{disabled} // FALSE;
   my $location_id = $event->location_id // 0;
   my $rs = $self->schema->resultset( 'Location');
   my $locations = [ map { [ $_, $_->id, {
         selected => $_->id eq $location_id ? TRUE : FALSE } ] }
                     $rs->search( {}, { order_by => 'address' } )->all ];

   return {
      class => 'standard-field', disabled => $disabled, type => 'select',
      value => [ [ NUL, undef ], @{ $locations } ], },
      original_location => { type => 'hidden', value => "${location_id}" };
};

my $_bind_trainer = sub {
   my ($self, $event, $opts) = @_;

   $opts->{training_event} or $event->event_type eq 'training' or return FALSE;

   my $disabled = $opts->{disabled} // FALSE;
   my $trainer  = ($event->trainers->all)[ 0 ] // NUL;
   my $trainers = $self->schema->resultset( 'Person' )->list_people
      ( 'trainer', { fields => { selected => "${trainer}" } } );

   return {
      class => 'standard-field', disabled => $disabled, type => 'select',
      value => [ [ NUL, undef ], @{ $trainers } ], },
      original_trainer => { type => 'hidden', value => "${trainer}" };
};

my $_bind_event_fields = sub {
   my ($self, $req, $event, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;
   my $no_maxp  = $disabled || $opts->{vehicle_event} ? TRUE : FALSE;

   return
   [  name             => $self->$_bind_event_name( $event, $opts ),
      start_date       => $_bind_start_date->( $req, $event, $opts ),
      owner            => $self->$_bind_owner( $event, $disabled ),
      description      => { class    => 'standard-field autosize server',
                            disabled => $disabled, type => 'textarea' },
      location         => $self->$_bind_location( $event, $opts ),
      start_time       => { class    => 'standard-field',
                            disabled => $disabled, type => 'time' },
# TODO: Needed for multiday events
#      end_date         => $_bind_end_date->( $req, $event, $opts ),
      end_time         => { class    => 'standard-field',
                            disabled => $disabled, type => 'time' },
      trainer          => $self->$_bind_trainer( $event, $opts ),
      max_participents => $no_maxp  ? FALSE : { class => 'standard-field' },
      notes            => $disabled ? FALSE : {
         class         => 'standard-field autosize', type => 'textarea' },
      ];
};

my $_create_event_post = sub {
   return shift->$_update_event_post( @_ );
};

my $_create_event = sub {
   my ($self, $req, $start_dt, $event_type, $opts) = @_; $opts //= {};

# TODO: Should not assume rota name
   my $attr  = { rota       => 'main',
                 start_date => $start_dt,
                 event_type => $event_type,
                 owner      => $req->username, };

   my $end_date = $req->body_params->( 'end_date', { optional => TRUE } );

   $attr->{end_date} = $end_date ? to_dt $end_date : $start_dt;
   $opts->{vrn} and $attr->{vehicle} = $opts->{vrn};
   $opts->{course} and $attr->{course_type} = $opts->{course};

   my $event = $self->schema->resultset( 'Event' )->new_result( $attr );

   $self->$_update_event_from_request( $req, $event );

   my $create = sub { $event->insert };

   if ($event_type eq 'training') {
      my $v = $req->body_params->( 'trainer', { optional => TRUE } );

      $v and $create = sub { $event->insert; $event->add_trainer( $v ) };
   }

   try   { $self->schema->txn_do( $create ) }
   catch {
      my $label = ($event->name || 'with no name on')
                . SPC.locd( $req, $start_dt );

      $self->blow_smoke( $_, 'create', 'event', $label );
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
   catch { $self->blow_smoke( $_, 'delete', 'event', $event->name ) };

   return $event;
};

my $_update_event = sub {
   my ($self, $req, $uri) = @_;

   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );

   $self->$_update_event_from_request( $req, $event );

   my $update = sub { $event->update };

   if ($event->event_type eq 'training') {
      my $trainer = $req->body_params->( 'trainer', { optional => TRUE } );
      my $original = $req->body_params->( 'original_trainer', {
         optional => TRUE } ) // NUL;

      if ($trainer and $trainer ne $original) {
         $update = sub {
            $event->update;
            $original and $event->remove_trainer( $original );
            $event->add_trainer( $trainer );
         };
      }
   }

   try   { $self->schema->txn_do( $update ) }
   catch { $self->blow_smoke( $_, 'update', 'event', $event->name ) };

   return $event;
};

# Public methods
sub create_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $date  = to_dt $req->body_params->( 'start_date' );
   my $event = $self->$_create_event( $req, $date, 'person' );

   $self->$_create_event_post( $req, $event->post_filename, $event );

   my $actionp  = $self->moniker.'/event';
   my $who      = $req->session->user_label;
   my $location = uri_for_action $req, $actionp, [ $event->uri ];
   my $message  = [ to_msg 'Event [_1] created by [_2]', $event->label, $who ];

   $self->send_event( $req, 'action:create-event event_uri:'.$event->uri );

   return { redirect => { location => $location, message => $message } };
}

sub create_training_event_action : Role(training_manager) {
   my ($self, $req) = @_;

   my $date = to_dt $req->body_params->( 'start_date' );
   my $course_name = $req->body_params->( 'name' );
   my $event = $self->$_create_event
      ( $req, $date, 'training', { course => $course_name } );
   my $uri = $event->uri;
   my $label = $event->localised_label( $req );
   my $who = $req->session->user_label;
   my $message = [ to_msg 'Training event [_1] created by [_2]', $label, $who ];
   my $actionp = $self->moniker.'/training_event';
   my $location = uri_for_action $req, $actionp, [ $uri ];

   $self->send_event( $req, "action:create-training-event event_uri:${uri}" );

   return { redirect => { location => $location, message => $message } };
}

sub create_vehicle_event_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->uri_params->( 0 );
   my $date     = to_dt $req->body_params->( 'start_date' );
   my $event    = $self->$_create_event
      ( $req, $date, 'vehicle', { vrn => $vrn } );
   my $uri      = $event->uri;
   my $label    = $event->label;
   my $who      = $req->session->user_label;
   my $location = $_vehicle_events_uri->( $req, $vrn );
   my $message  = [ to_msg 'Vehicle event [_1] created by [_2]', $label, $who ];

   $self->send_event( $req, "action:create-vehicle-event event_uri:${uri}" );

   return { redirect => { location => $location, message => $message } };
}

sub delete_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $uri   = $req->uri_params->( 0 );
   my $event = $self->$_delete_event( $uri );
   my $label = $event->label;

   $self->$_delete_event_post( $req, $event->post_filename );

   my $who      = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/events';
   my $message  = [ to_msg 'Event [_1] deleted by [_2]', $label, $who ];

   $self->send_event( $req, "action:delete-event event_uri:${uri}" );

   return { redirect => { location => $location, message => $message } };
}

sub delete_training_event_action : Role(training_manager) {
   my ($self, $req) = @_;

   my $uri = $req->uri_params->( 0 );
   my $event = $self->$_delete_event( $uri );
   my $label = $event->localised_label( $req );
   my $who = $req->session->user_label;
   my $message = [ to_msg 'Training event [_1] deleted by [_2]', $label, $who ];
   my $location = uri_for_action $req, 'train/events';

   $self->send_event( $req, "action:delete-training-event event_uri:${uri}" );

   return { redirect => { location => $location, message => $message } };
}

sub delete_vehicle_event_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->uri_params->( 0 );
   my $uri      = $req->uri_params->( 1 );
   my $event    = $self->$_delete_event( $uri );
   my $label    = $event->label;
   my $who      = $req->session->user_label;
   my $location = $_vehicle_events_uri->( $req, $vrn );
   my $message  = "action:delete-vehicle-event event_uri:${uri} vehicle:${vrn}";

   $self->send_event( $req, $message );
   $message = [ to_msg 'Vehicle event [_1] deleted by [_2]', $label, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub event : Role(event_manager) {
   my ($self, $req) = @_;

   my $actionp    =  $self->moniker.'/event';
   my $opts       =  { optional => TRUE };
   my $uri        =  $req->uri_params->( 0, $opts );
   my $date       =  $req->query_params->( 'date', $opts );
   my $href       =  uri_for_action $req, $actionp, [ $uri ];
   my $form       =  blank_form 'event-admin', $href;
   my $action     =  $uri ? 'update' : 'create';
   my $page       =  {
      first_field => 'name',
      forms       => [ $form ],
      literal_js  => $self->$_add_event_js(),
      selected    => $req->query_params->( 'before', $opts ) ? 'previous_events'
                  :  'current_events',
      title       => loc $req, "event_${action}_heading" };
   my $event      =  $self->$_maybe_find_event( $uri );
   my $links      =  $uri ? $_event_ops_links->( $req, $actionp, $uri ) : [];
   my $disabled   =  $page->{selected} ne 'current_events' ? TRUE : FALSE;

   $uri and p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_fields $form, $self->schema, 'Event', $event,
      $self->$_bind_event_fields( $req, $event, {
         date => $date, disabled => $disabled } );

   $disabled
      or p_action $form, $action, [ 'event', $uri ], { request => $req };

   $uri and p_action $form, 'delete', [ 'event', $uri ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub event_info : Dialog Role(any) {
   my ($self, $req) = @_;

   my $uri   = $req->uri_params->( 0 );
   my $event = $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $stash = $self->dialog_stash( $req );
   my $form  = $stash->{page}->{forms}->[ 0 ] = blank_form;
   my $label = $event->owner->label;
   my $title = $event->name;
   my ($start, $end) = display_duration $req, $event;

   $event->owner->postcode and $label .= ' ('.$event->owner->outer_postcode.')';

   p_tag $form, 'p', $title, { class => 'label-column' };
   p_tag $form, 'p', $label, { class => 'label-column' };
   p_tag $form, 'p', $start, { class => 'label-column' };
   p_tag $form, 'p', $end,   { class => 'label-column' };

   return $stash;
}

sub event_summary : Role(any) {
   my ($self, $req) = @_;

   my $actionp =  $self->moniker.'/event';
   my $schema  =  $self->schema;
   my $user    =  $req->username;
   my $uri     =  $req->uri_params->( 0 );
   my $event   =  $schema->resultset( 'Event' )->find_event_by( $uri );
   my $person  =  $schema->resultset( 'Person' )->find_by_shortcode( $user );
   my $href    =  uri_for_action $req, $actionp, [ $uri ];
   my $form    =  blank_form 'event-admin', $href;
   my $opts    =  { optional => TRUE };
   my $page    =  {
      forms    => [ $form ],
      selected => $event->event_type eq 'training' ? 'training_events'
               :  now_dt > $event->start_date ? 'previous_events'
               :  'current_events',
      title    => loc $req, 'event_summary_heading' };
   my $links   =  $_event_ops_links->( $req, $actionp, $uri );

   $uri and p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_fields $form, $self->schema, 'Event', $event,
      $self->$_bind_event_fields( $req, $event, { disabled => TRUE } );

   $_add_participate_button->( $req, $form, $event, $person );

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
   my $form      =  blank_form;
   my $form_name =  $after  ? 'current_events'
                 :  $before ? 'previous_events'
                 :            'events_management';
   my $page      =  {
      forms      => [ $form ],
      selected   => $form_name,
      title      => loc $req, "${form_name}_heading" };
   my $links     =  $_events_ops_links->( $req, $moniker, $params, $pager );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, { headers => $_events_headers->( $req ) };

   p_row $table, [ map { $self->$_event_links( $req, $_ ) } $events->all ];

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub message : Dialog Role(event_manager) {
   return $_[ 0 ]->message_stash( $_[ 1 ] );
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
   my $message   = [ to_msg 'Event [_1] attendee [_2]', $uri, $person->label ];

   $self->send_event( $req, "action:participate-in-event event_uri:${uri}" );

   return { redirect => { location => $location, message => $message } };
}

sub participents : Role(any) {
   my ($self, $req) = @_;

   my $uri       =  $req->uri_params->( 0 );
   my $event     =  $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $disabled  =  now_dt > $event->start_date ? TRUE : FALSE;
   my $params    =  { event => $uri };
   my $actionp   =  $self->moniker.'/participents';
   my $href      =  uri_for_action $req, $actionp, [ $uri ], $params;
   my $form      =  blank_form 'message-participents', $href, {
      class      => 'wider-table', id => 'message-participents' };
   my $page      =  {
      disabled   => $disabled,
      forms      => [ $form ],
      selected   => $event->event_type eq 'training' ? 'training_events'
                 :  $disabled ? 'previous_events'
                 :  'current_events',
      title      => $_participents_title->( $req, $event ) };
   my $links     =  $self->$_participent_ops_links( $req, $page, $params );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, { headers => $_participent_headers->( $req ) };
   my $person_rs = $self->schema->resultset( 'Person' );

   p_row $table, [ map { $self->$_participent_links( $req, $page, $event, $_ ) }
                      @{ $person_rs->list_participents( $event ) } ];

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub training_event : Role(training_manager) {
   my ($self, $req) = @_;

   my $uri  = $req->uri_params->( 0, { optional => TRUE } );
   my $date = $req->query_params->( 'date', { optional => TRUE } );
   my $href = uri_for_action $req, $self->moniker.'/training_event', [ $uri ];
   my $form = blank_form 'training-event', $href;
   my $action = $uri ? 'update' : 'create';
   my $page = {
      forms => [ $form ], selected => 'training_events',
      title => locm $req, 'training_event_title',
   };
   my $event = $self->$_maybe_find_event( $uri );
   my $args = [ 'training_event', $uri ];

   p_fields $form, $self->schema, 'Event', $event,
      $self->$_bind_event_fields( $req, $event, {
         date => $date, training_event => TRUE } );

   p_action $form, $action, $args, { request => $req };

   $uri and p_action $form, 'delete', $args, { request => $req };

   return $self->get_stash( $req, $page );
}

sub unparticipate_event_action : Role(any) {
   my ($self, $req) = @_;

   my $user      = $req->username;
   my $uri       = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_by_shortcode( $user );

   $person->delete_participent_for( $uri );

   my $who       = $person->label;
   my $actionp   = $self->moniker.'/event_summary';
   my $location  = uri_for_action $req, $actionp, [ $uri ];
   my $message   = [ to_msg 'Event [_1] attendence cancelled for [_2]',
                     $uri, $who ];

   $self->send_event( $req, "action:unparticipate-in-event event_uri:${uri}" );

   return { redirect => { location => $location, message => $message } };
}

sub update_event_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $uri   = $req->uri_params->( 0 );
   my $event = $self->$_update_event( $req, $uri );

   $self->$_update_event_post( $req, $event->post_filename, $event );

   my $who      = $req->session->user_label;
   my $actionp  = $self->moniker.'/event';
   my $location = uri_for_action $req, $actionp, [ $uri ];
   my $message  = [ to_msg 'Event [_1] updated by [_2]', $event->label, $who ];

   $self->send_event( $req, "action:update-event event_uri:${uri}" );

   return { redirect => { location => $location, message => $message } };
}

sub update_training_event_action : Role(training_manager) {
   my ($self, $req) = @_;

   my $uri = $req->uri_params->( 0 );
   my $event = $self->$_update_event( $req, $uri );
   my $who = $req->session->user_label;
   my $label = $event->localised_label( $req );
   my $message = [ to_msg 'Training event [_1] updated by [_2]', $label, $who ];
   my $actionp = $self->moniker.'/training_event';
   my $location = uri_for_action $req, $actionp, [ $uri ];

   $self->send_event( $req, "action:update-training-event event_uri:${uri}" );

   return { redirect => { location => $location, message => $message } };
}

sub update_vehicle_event_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->uri_params->( 0 );
   my $uri      = $req->uri_params->( 1 );
   my $event    = $self->$_update_event( $req, $uri );
   my $location = $_vehicle_events_uri->( $req, $vrn );
   my $message  = "action:update-vehicle-event event_uri:${uri} vehicle:${vrn}";

   $self->send_event( $req, $message );

   my $label = $event->label; my $who = $req->session->user_label;

   $message = [ to_msg 'Vehicle event [_1] updated by [_2]', $label, $who ];

   return { redirect => { location => $location, message => $message } };
};

sub vehicle_event : Role(rota_manager) {
   my ($self, $req) = @_;

   my $actionp    =  $self->moniker.'/vehicle_event';
   my $vrn        =  $req->uri_params->( 0, { optional => TRUE } );
   my $uri        =  $req->uri_params->( 1, { optional => TRUE } );
   my $href       =  uri_for_action $req, $actionp, [ $vrn, $uri ];
   my $form       =  blank_form 'vehicle-event-admin', $href;
   my $action     =  $uri ? 'update' : 'create';
   my $page       =  {
      first_field => 'name',
      forms       => [ $form ],
      literal_js  => $self->$_add_event_js(),
      selected    => 'service_vehicles',
      title       => loc $req, "vehicle_event_${action}_heading" };
   my $event      =  $self->$_maybe_find_event( $uri );
   my $label      =  $uri ? $event->vehicle->label : $vrn;
   my $args       =  [ 'vehicle_event', $label ];

   p_textfield $form, 'vehicle', $label, { disabled => TRUE };

   p_fields $form, $self->schema, 'Event', $event,
      $self->$_bind_event_fields( $req, $event, { vehicle_event => TRUE } );

   p_action $form, $action, $args, { request => $req };

   $uri and p_action $form, 'delete', $args, { request => $req };

   return $self->get_stash( $req, $page );
}

sub vehicle_info : Dialog Role(rota_manager) {
   my ($self, $req) = @_;

   my $uri     = $req->uri_params->( 0 );
   my $event   = $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $stash   = $self->dialog_stash( $req );
   my $form    = $stash->{page}->{forms}->[ 0 ] = blank_form;
   my $owner   = $event->owner->label;
   my $vehicle = $event->vehicle->label;
   my $title   = $event->name;

   my ($start, $end) = display_duration $req, $event;

   $event->owner->postcode and $owner .= ' ('.$event->owner->outer_postcode.')';

   p_tag $form, 'p', $title,   { class => 'label-column' };
   p_tag $form, 'p', $owner,   { class => 'label-column' };
   p_tag $form, 'p', $vehicle, { class => 'label-column' };
   p_tag $form, 'p', $start,   { class => 'label-column' };
   p_tag $form, 'p', $end,     { class => 'label-column' };

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
