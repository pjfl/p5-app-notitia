package App::Notitia::Model::Vehicle;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link f_tag p_action p_button
                                p_date p_fields p_hidden p_list
                                p_row p_select p_table p_tag p_textfield );
use App::Notitia::Util      qw( assign_link check_field_js display_duration
                                loc local_dt now_dt make_tip management_link
                                page_link_set register_action_paths
                                set_element_focus slot_identifier time2int
                                to_dt to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

# Public attributes
has '+moniker' => default => 'asset';

register_action_paths
   'asset/assign'          => 'vehicle-assign',
   'asset/request_info'    => 'vehicle-request-info',
   'asset/request_vehicle' => 'vehicle-request',
   'asset/unassign'        => 'vehicle-assign',
   'asset/vehicle'         => 'vehicle',
   'asset/vehicle_events'  => 'vehicle-events',
   'asset/vehicles'        => 'vehicles';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_compare_forward = sub {
   my ($x, $y) = @_;

   $x->[ 0 ]->start_date < $y->[ 0 ]->start_date and return -1;
   $x->[ 0 ]->start_date > $y->[ 0 ]->start_date and return  1;

   $x = time2int $x->[ 1 ]->[ 2 ]->{value};
   $y = time2int $y->[ 1 ]->[ 2 ]->{value};

   $x < $y and return -1; $x > $y and return 1; return 0;
};

my $_compare_reverse = sub { # Duplication for efficiency
   my ($y, $x) = @_;

   $x->[ 0 ]->start_date < $y->[ 0 ]->start_date and return -1;
   $x->[ 0 ]->start_date > $y->[ 0 ]->start_date and return  1;

   $x = time2int $x->[ 1 ]->[ 2 ]->{value};
   $y = time2int $y->[ 1 ]->[ 2 ]->{value};

   $x < $y and return -1; $x > $y and return 1; return 0;
};

my $_create_action = sub {
   return { action => 'create', container_class => 'add-link',
            request => $_[ 0 ] };
};

my $_find_vreq_by = sub {
   my ($schema, $event, $vehicle_type) = @_;

   my $rs = $schema->resultset( 'VehicleRequest' );

   return $rs->search( { event_id => $event->id,
                         type_id  => $vehicle_type->id } )->single;
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

my $_maybe_find_vehicle = sub {
   my ($schema, $vrn) = @_; $vrn or return Class::Null->new;

   my $rs = $schema->resultset( 'Vehicle' );

   return $rs->find_vehicle_by( $vrn, { prefetch => [ 'type' ] } );
};

my $_owner_list = sub {
   my ($schema, $vehicle, $disabled) = @_;

   my $opts   = { fields => { selected => $vehicle->owner } };
   my $people = $schema->resultset( 'Person' )->list_all_people( $opts );

   $opts = { name  => 'owner_id', numify => TRUE,
             type  => 'select',   value  => [ [ NUL, NUL ], @{ $people } ] };
   $disabled and $opts->{disabled} = TRUE;

   return $opts;
};

my $_quantity_list = sub {
   my ($type, $selected) = @_;

   my $select = { class => 'single-digit-select narrow', };
   my $opts   = { class => 'single-digit', label => NUL };
   my $values = [ [ 0, 0 ], [ 1, 1 ], [ 2, 2 ], [ 3, 3 ], [ 4, 4 ], ];

   $values->[ $selected ]->[ 2 ] = { selected => TRUE };

   p_select $select , "${type}_quantity", $values, $opts;

   return $select;
};

my $_transport_links = sub {
   my ($self, $req, $event) = @_; my @links;

   my $moniker = $self->moniker; my $uri = $event->uri;

   push @links, {
      value => management_link
         ( $req, "${moniker}/request_vehicle", 'edit', { args => [ $uri ] } ) };

   return @links;
};

my $_update_vehicle_req_from_request = sub {
   my ($req, $vreq, $vehicle_type) = @_;

   my $v = $req->body_params->( "${vehicle_type}_quantity" );

   defined $v and $vreq->quantity( $v );

   return;
};

my $_vehicle_events_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "vehicle_events_heading_${_}" ) } }
            0 .. 4 ];
};

my $_vehicle_event_links = sub {
   my ($self, $req, $event) = @_; my @links;

   my $uri = $event->uri; my $vrn = $event->vehicle->vrn;

   push @links, {
      value => management_link
         ( $req, 'event/vehicle_event', 'edit', { args => [ $vrn, $uri ] } ) };

   return @links;
};

my $_vehicle_js = sub {
   my $vrn  = shift;
   my $opts = { domain => $vrn ? 'update' : 'insert', form => 'Vehicle' };

   return [ check_field_js( 'vrn', $opts ) ];
};

my $_vehicle_slot_links = sub {
   my ($self, $req, $slot) = @_; my @links;

   my $type = $slot->rota_type;
   my $date = $slot->date->clone->set_time_zone( 'local' )->ymd;

   push @links, {
      value => management_link
         ( $req, 'day/day_rota', 'edit', { args => [ $type, $date ] } ) };

   return @links;
};

my $_vehicle_request_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "vehicle_request_heading_${_}" ) } }
            0 .. 5 ];
};

my $_vehicle_title = sub {
   my ($req, $type, $private, $service) = @_;

   my $k = 'vehicles_management_heading';

   if    ($private) { $k = 'vehicle_private_heading' }
   elsif ($service) { $k = 'vehicle_service_heading' }
   elsif ($type)    { $k = "${type}_list_link" }

   return loc $req, $k;
};

my $_vehicle_type_tuple = sub {
   my ($type, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{selected} //= NUL;
   $opts->{selected}   = $opts->{selected} eq $type ? TRUE : FALSE;

   return [ $type->name, $type, $opts ];
};

my $_vehicles_headers = sub {
   my ($req, $service) = @_; my $max = $service ? 5 : 2;

   return [ map { { value => loc( $req, "vehicles_heading_${_}" ) } }
            0 .. $max ];
};

my $_find_or_create_vreq = sub {
   my ($schema, $event, $vehicle_type) = @_;

   my $vreq = $_find_vreq_by->( $schema, $event, $vehicle_type );

   $vreq and return $vreq; my $rs = $schema->resultset( 'VehicleRequest' );

   return $rs->new_result( { event_id => $event->id,
                             type_id  => $vehicle_type->id } );
};

my $_list_vehicle_types = sub {
   my ($schema, $opts) = @_; $opts = { %{ $opts // {} } };

   my $fields  = delete $opts->{fields} // {};
   my $type_rs = $schema->resultset( 'Type' );

   return [ map { $_vehicle_type_tuple->( $_, $fields ) }
            $type_rs->search_for_vehicle_types( $opts )->all ];
};

my $_req_quantity = sub {
   my ($schema, $event, $vehicle_type) = @_;

   my $vreq = $_find_vreq_by->( $schema, $event, $vehicle_type );

   return $vreq ? $vreq->quantity : 0;
};

my $_select_nav_link_name = sub {
   my $opts = { %{ $_[ 0 ] } };

   return $opts->{private} ? 'private_vehicles'
      :   $opts->{service} ? 'service_vehicles'
      :   'vehicles_list';
};

my $_vehicle_type_list = sub {
   my ($schema, $vehicle, $disabled) = @_;

   my $opts   = { fields => { selected => $vehicle->type } };
   my $values = [ [ NUL, NUL ], @{ $_list_vehicle_types->( $schema, $opts ) } ];

   $opts = { class => 'standard-field required', label  => 'vehicle_type',
             name  => 'type',                    numify => TRUE,
             type  => 'select',                  value  => $values };
   $disabled and $opts->{disabled} = TRUE;

   return $opts;
};

my $_vreq_row = sub {
   my ($schema, $req, $page, $event, $vehicle_type) = @_;

   my $uri    = $page->{event_uri};
   my $rs     = $schema->resultset( 'Transport' );
   my $tports = $rs->search_for_vehicle_by_type( $event->id, $vehicle_type->id);
   my $quant  = $_req_quantity->( $schema, $event, $vehicle_type );
   my $row    = [ { value => loc( $req, $vehicle_type ) },
                  $_quantity_list->( $vehicle_type, $quant ) ];

   $quant or return $row;

   for my $slotno (0 .. $quant - 1) {
      my $transport = $tports->next;
      my $vehicle   = $transport ? $transport->vehicle : undef;
      my $opts      = { name        => "${vehicle_type}_event_${slotno}",
                        operator    => $event->owner,
                        type        => $vehicle_type,
                        vehicle     => $vehicle,
                        vehicle_req => TRUE, };

      push @{ $row }, assign_link( $req, $page, [ $uri ], $opts );
   }

   return $row;
};

my $_bind_vehicle_fields = sub {
   my ($schema, $req, $vehicle, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;

   return
   [  vrn      => { class    => 'standard-field server',
                    disabled => $disabled },
      type     => $_vehicle_type_list->( $schema, $vehicle, $disabled ),
      name     => { disabled => $disabled,
                    label    => 'vehicle_name',
                    tip      => make_tip $req, 'vehicle_name_field_tip' },
      owner    => $_owner_list->( $schema, $vehicle, $disabled ),
      colour   => { disabled => $disabled,
                    tip      => make_tip $req, 'vehicle_colour_field_tip' },
      aquired  => { disabled => $disabled, type => 'date' },
      disposed => { class    => 'standard-field clearable',
                    disabled => $disabled, type => 'date' },
      notes    => { class    => 'standard-field autosize',
                    disabled => $disabled, type => 'textarea' },
      ];
};

# Private methods
my $_toggle_event_assignment = sub {
   my ($self, $req, $vrn, $action) = @_;

   my $schema = $self->schema;
   my $uri = $req->uri_params->( 0 );
   my $vehicle = $schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );
   my $method = $action eq 'assign' ? 'assign_to_event' : 'unassign_from_event';

   $vehicle->$method( $uri, $req->username );

   my $prep = $action eq 'assign' ? 'to' : 'from';
   my $key  = "Vehicle [_1] ${action}ed ${prep} [_2] by [_3]";
   my $event = $schema->resultset( 'Event' )->find_event_by( $uri );
   my $scode = $event->owner;
   my $dmy = local_dt( $event->start_date )->dmy( '/' );
   my $message = "action:vehicle-${action}ment event_uri:${uri} "
               . "shortcode:${scode} date:${dmy} vehicle:${vrn}";

   $self->send_event( $req, $message );
   $message = [ to_msg $key, $vrn, $uri, $req->session->user_label ];

   return { redirect => { message => $message } }; # location referer
};

my $_toggle_slot_assignment = sub {
   my ($self, $req, $vrn, $action) = @_;

   my $params = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $slot_name = $params->( 2 );
   my $schema = $self->schema;
   my $vehicle = $schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );
   my $method = "${action}_slot";
   my $rota_dt = to_dt( $rota_date );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $slot_name, 3;

   my $slot = $vehicle->$method( $rota_name, $rota_dt, $shift_type,
                                 $slot_type, $subslot, $req->username );

   my $prep = $action eq 'assign' ? 'to' : 'from';
   my $key = "Vehicle [_1] ${action}ed ${prep} [_2] by [_3]";
   my $label = slot_identifier
      ( $rota_name, $rota_date, $shift_type, $slot_type, $subslot );
   my $operator = $slot->operator;
   my $dmy = local_dt( $rota_dt )->dmy( '/' );
   my $message = "action:vehicle-${action}ment date:${dmy} "
               . "shortcode:${operator} slot_key:${slot_name} vehicle:${vrn}";

   $self->send_event( $req, $message );
   $message = [ to_msg $key, $vrn, $label, $req->session->user_label ];

   return { redirect => { message => $message } }; # location referer
};

my $_toggle_assignment = sub {
   my ($self, $req, $action) = @_;

   my $params = $req->uri_params; my $rota_name = $params->( 0 ); my $r;

   my $vrn = $req->body_params->( 'vehicle', { optional => TRUE } );

   unless ($vrn) {
      $vrn = $req->body_params->( 'vehicle_original' ); $action = 'unassign';
   }

   try   { $self->schema->resultset( 'Type' )->find_rota_by( $rota_name ) }
   catch { $r = $self->$_toggle_event_assignment( $req, $vrn, $action ) };

   $r and return $r;

   return $self->$_toggle_slot_assignment( $req, $vrn, $action );
};

my $_update_vehicle_from_request = sub {
   my ($self, $req, $vehicle) = @_; my $params = $req->body_params; my $v;

   my $opts = { optional => TRUE };

   for my $attr (qw( aquired colour disposed name notes vrn )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      length $v and is_member $attr, [ qw( aquired disposed ) ]
         and $v = to_dt $v;

      $vehicle->$attr( $v );
   }

   $v = $params->( 'owner', $opts ); $vehicle->owner_id( $v ? $v : undef );
   $v = $params->( 'type', $opts ); defined $v and $vehicle->type_id( $v );

   return;
};

my $_vehicle_events = sub {
   my ($self, $req, $opts) = @_; my @rows;

   my $event_rs = $self->schema->resultset( 'Event' );
   my $slot_rs  = $self->schema->resultset( 'Slot' );
   my $tport_rs = $self->schema->resultset( 'Transport' );

   for my $slot ($slot_rs->search_for_assigned_slots( $opts )->all) {
      push @rows,
         [ $slot,
           [ { value => $slot->label( $req ) },
             { value => $slot->operator->label },
             { value => $slot->start_time },
             { value => $slot->end_time },
             $self->$_vehicle_slot_links( $req, $slot ) ] ];
   }

   $opts->{prefetch} = [ 'end_rota', 'owner', 'location', 'start_rota' ];

   for my $event ($event_rs->search_for_events( $opts )->all) {
      push @rows,
         [ $event,
           [ { value => $event->label },
             { value => $event->owner->label },
             { value => $event->start_time },
             { value => $event->end_time },
             $self->$_vehicle_event_links( $req, $event ) ] ];
   }

   $opts->{prefetch} = [ { 'event' => [ 'owner', 'start_rota' ] }, 'vehicle' ];

   for my $tport ($tport_rs->search_for_assigned_vehicles( $opts )->all) {
      my $event = $tport->event;

      push @rows,
         [ $event,
           [ { value => $event->label },
             { value => $event->owner->label },
             { value => $event->start_time },
             { value => $event->end_time },
             $self->$_transport_links( $req, $event ) ] ];
   }

   my $compare = exists $opts->{before} ? $_compare_reverse : $_compare_forward;

   return [ sort { $compare->( $a, $b ) } @rows ];
};

my $_vehicle_links = sub {
   my ($self, $req, $service, $vehicle) = @_; my $moniker = $self->moniker;

   my $vrn = $vehicle->vrn; my $links = [ { value => $vehicle->label } ];

   push @{ $links }, { value => loc $req, $vehicle->type };

   push @{ $links },
      { value => management_link( $req, "${moniker}/vehicle", $vrn, {
         params => $req->query_params->( { optional => TRUE } ) } ) };

   $service or return $links;

   my $now  = now_dt;
   my $opts = $_create_action->( $req );
   my $href = uri_for_action $req, 'event/vehicle_event', [ $vrn ];

   push @{ $links }, { value => f_link 'event', $href, $opts };

   push @{ $links },
      { value => management_link( $req, "${moniker}/vehicle_events", $vrn, {
         params => { after => $now->subtract( days => 1 )->ymd } } ) };

   my $keeper = $self->find_last_keeper( $req, $now, $vehicle );

   push @{ $links }, { value => $keeper ? $keeper->[ 0 ]->label : NUL };

   return $links;
};

my $_vehicles_ops_links = sub {
   my ($self, $req, $params, $pager) = @_; my $moniker = $self->moniker;

   my $actionp = "${moniker}/vehicles";
   my $page_links = page_link_set $req, $actionp, [], $params, $pager;
   my $href = uri_for_action $req, "${moniker}/vehicle";
   my $links = [ f_link 'vehicle', $href, $_create_action->( $req ) ];

   $page_links and unshift @{ $links }, $page_links;

   return $links;
};

# Public methods
sub assign : Dialog Role(rota_manager) {
   my ($self, $req) = @_; my $params = $req->uri_params;

   my $args = [ $params->( 0 ) ]; my $opts = { optional => TRUE };

   my $rota_date = $params->( 1, $opts );
      $rota_date and push @{ $args }, $rota_date;

   my $slot_name = $params->( 2, $opts );
      $slot_name and push @{ $args }, $slot_name;

   my $action = $req->query_params->( 'action' );
   my $type   = $req->query_params->( 'type', { optional => TRUE } ) // 'bike';
   my $stash  = $self->dialog_stash( $req );
   my $href   = uri_for_action $req, $self->moniker.'/vehicle', $args;
   my $form   = $stash->{page}->{forms}->[ 0 ]
              = blank_form "${action}-vehicle", $href;
   my $page   = $stash->{page};

   if ($action eq 'assign') {
      my $where  = { service => TRUE, type => $type };
      my $rs     = $self->schema->resultset( 'Vehicle' );
      my $values = [ [ NUL, NUL ], @{ $rs->list_vehicles( $where ) } ];

      p_select $form, 'vehicle', $values, {
         class => 'right-last', label => NUL };
      $page->{literal_js} = set_element_focus 'assign-vehicle', 'vehicle';
   }
   else { p_hidden $form, 'vehicle', $req->query_params->( 'vehicle' ) }

   p_button $form, 'confirm', "${action}_vehicle", {
      class => 'button right-last' };

   return $stash;
}

sub assign_vehicle_action : Role(rota_manager) {
   return $_[ 0 ]->$_toggle_assignment( $_[ 1 ], 'assign' );
}

sub create_vehicle_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vehicle = $self->schema->resultset( 'Vehicle' )->new_result( {} );

   $self->$_update_vehicle_from_request( $req, $vehicle );

   try   { $vehicle->insert }
   catch { $self->blow_smoke( $_, 'create', 'vehicle', $vehicle->vrn ) };

   my $vrn = $vehicle->vrn;
   my $who = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/vehicle', [ $vrn ];
   my $message = [ to_msg 'Vehicle [_1] created by [_2]', $vrn, $who ];

   $self->send_event( $req, "action:create-vehicle vehicle:${vrn}" );

   return { redirect => { location => $location, message => $message } };
}

sub delete_vehicle_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn = $req->uri_params->( 0 );
   my $vehicle = $self->schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

   $vehicle->delete;

   my $who = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/vehicles';
   my $message = [ to_msg 'Vehicle [_1] deleted by [_2]', $vrn, $who ];

   $self->send_event( $req, "action:delete-vehicle vehicle:${vrn}" );

   return { redirect => { location => $location, message => $message } };
}

sub find_last_keeper {
   my ($self, $req, $now, $vehicle) = @_; my $keeper;

   my $tommorrow = $now->clone->truncate( to => 'day' )->add( days => 1 );
   my $opts      = { before     => $tommorrow,
                     event_type => 'vehicle',
                     page       => 1,
                     vehicle    => $vehicle->vrn,
                     rows       => 10, };

   for my $tuple (@{ $self->$_vehicle_events( $req, $opts ) }) {
      my ($start_dt) = $tuple->[ 0 ]->duration; $start_dt > $now and next;

      my $attr = $tuple->[ 0 ]->can( 'owner' ) ? 'owner' : 'operator';
      my $event; $attr eq 'owner' and $event = $tuple->[ 0 ];

      my $location; $event and $event->event_type eq 'vehicle'
         and $location = $event->location;

      $keeper = [ $tuple->[ 0 ]->$attr(), $location ]; last;
   }

   return $keeper;
}

sub request_info : Dialog Role(rota_manager) {
   my ($self, $req) = @_;

   my $uri     = $req->uri_params->( 0 );
   my $event   = $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $stash   = $self->dialog_stash( $req );
   my $vreq_rs = $self->schema->resultset( 'VehicleRequest' );
   my $form    = $stash->{page}->{forms}->[ 0 ] = blank_form;
   my $id      = $event->id;

   my ($start, $end) = display_duration $req, $event;

   p_tag $form, 'p', $event->name;
   p_tag $form, 'p', $start; p_tag $form, 'p', $end;

   for my $tuple ($vreq_rs->search_for_request_info( { event_id => $id } )) {
      p_tag $form, 'p', $tuple->[ 1 ].' x '.loc( $req, $tuple->[ 0 ]->type );
   }

   return $stash;
}

sub request_vehicle : Role(rota_manager) Role(event_manager) {
   my ($self, $req) = @_;

   my $schema   =  $self->schema;
   my $uri      =  $req->uri_params->( 0 );
   my $event    =  $schema->resultset( 'Event' )->find_event_by
                   ( $uri, { prefetch => [ 'owner' ] } );
   my $href     =  uri_for_action $req, $self->moniker.'/vehicle', [ $uri ];
   my $form     =  blank_form 'vehicle-request', $href, {
      class     => 'wide-form no-header-wrap' };
   my $page     =  {
      event_uri => $uri,
      forms     => [ $form ],
      moniker   => $self->moniker,
      selected  => $event->event_type eq 'training' ? 'training_events'
                :  now_dt > $event->start_date ? 'previous_events'
                :  'current_events',
      title     => loc $req, 'vehicle_request_heading' };
   my $type_rs  =  $schema->resultset( 'Type' );

   p_textfield $form, 'name', $event->name, {
      disabled => TRUE, label => 'event_name' };

   p_date $form, 'start_date', $event->start_date, { disabled => TRUE };

   my $table = p_table $form, { headers => $_vehicle_request_headers->( $req )};

   p_row $table, [ map { $_vreq_row->( $schema, $req, $page, $event, $_ ) }
                   $type_rs->search_for_vehicle_types->all ];

   $page->{selected} eq 'current_events'
      and p_button $form, 'request_vehicle', 'request_vehicle', {
         class => 'save-button right-last' };

   return $self->get_stash( $req, $page );
}

sub request_vehicle_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $schema  = $self->schema;
   my $uri     = $req->uri_params->( 0 );
   my $event   = $schema->resultset( 'Event' )->find_event_by( $uri );
   my $type_rs = $schema->resultset( 'Type' );

   for my $vehicle_type ($type_rs->search_for_types( 'vehicle' )->all) {
      my $vreq = $_find_or_create_vreq->( $schema, $event, $vehicle_type );

      $_update_vehicle_req_from_request->( $req, $vreq, $vehicle_type );

      if ($vreq->in_storage) { $vreq->update } else { $vreq->insert }

      my $quantity = $vreq->quantity // 0;
      my $message  = "action:request-vehicle event_uri:${uri} "
                   . "vehicletype:${vehicle_type} quantity:${quantity}";

      $quantity > 0 and $self->send_event( $req, $message );
   }

   my $actionp  = $self->moniker.'/request_vehicle';
   my $location = uri_for_action $req, $actionp, [ $uri ];
   my $message  = [ to_msg 'Vehicle request for event [_1] updated by [_2]',
                    $event->label, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub unassign_vehicle_action : Role(rota_manager) {
   return $_[ 0 ]->$_toggle_assignment( $_[ 1 ], 'unassign' );
}

sub update_vehicle_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn     = $req->uri_params->( 0 );
   my $vehicle = $self->schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

   $self->$_update_vehicle_from_request( $req, $vehicle );

   try   { $vehicle->update }
   catch { $self->blow_smoke( $_, 'delete', 'vehicle', $vehicle->vrn ) };

   my $who      = $req->session->user_label; $vrn = $vehicle->vrn;
   my $location = uri_for_action $req, $self->moniker.'/vehicle', [ $vrn ];
   my $message  = [ to_msg 'Vehicle [_1] updated by [_2]', $vrn, $who ];

   $self->send_event( $req, "action:update-vehicle vehicle:${vrn}" );

   return { redirect => { location => $location, message => $message } };
}

sub vehicle : Role(rota_manager) {
   my ($self, $req) = @_;

   my $actionp    =  $self->moniker.'/vehicle';
   my $vrn        =  $req->uri_params->( 0, { optional => TRUE } );
   my $service    =  $req->query_params->( 'service', { optional => TRUE } );
   my $private    =  $req->query_params->( 'private', { optional => TRUE } );
   my $href       =  uri_for_action $req, $actionp, [ $vrn ];
   my $form       =  blank_form 'vehicle-admin', $href;
   my $action     =  $vrn ? 'update' : 'create';
   my $page       =  {
      first_field => 'vrn',
      forms       => [ $form ],
      literal_js  => $_vehicle_js->( $vrn ),
      selected    => $service ? 'service_vehicles'
                  :  $private ? 'private_vehicles' : 'vehicles_list',
      title       => loc $req, "vehicle_${action}_heading" };
   my $schema     =  $self->schema;
   my $vehicle    =  $_maybe_find_vehicle->( $schema, $vrn );
   my $fields     =  $_bind_vehicle_fields->( $schema, $req, $vehicle );
      $href       =  uri_for_action $req, $actionp;
   my $links      =  [ f_link 'vehicle', $href, $_create_action->( $req ) ];
   my $args       =  [ 'vehicle', $vehicle->label ];

   $vrn and p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_fields $form, $self->schema, 'Vehicle', $vehicle, $fields;

   p_action $form, $action, $args, { request => $req };

   $vrn and p_action $form, 'delete', $args, { request => $req };

   return $self->get_stash( $req, $page );
}

sub vehicle_events : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn    =  $req->uri_params->( 0 );
   my $params =  $req->query_params;
   my $after  =  $params->( 'after',  { optional => TRUE } );
   my $before =  $params->( 'before', { optional => TRUE } );
# TODO: Add paged query in case of search for vehicle event before tommorrow
   my $opts   =  { after      => $after  ? to_dt( $after  ) : FALSE,
                   before     => $before ? to_dt( $before ) : FALSE,
                   event_type => 'vehicle',
                   vehicle    => $vrn, };
   my $form   =  blank_form { class => 'wide-form no-header-wrap' };
   my $page   =  {
      forms   => [ $form ], selected => 'service_vehicles',
      title   => loc $req, 'vehicle_events_management_heading' };

   p_textfield $form, 'vehicle', $vrn, { disabled => TRUE };

   my $table  = p_table $form, { headers => $_vehicle_events_headers->( $req )};
   my $events = $self->$_vehicle_events( $req, $opts );

   p_row $table, [ map { $_->[ 1 ] } @{ $events } ];

   my $href   = uri_for_action $req, 'event/vehicle_event', [ $vrn ];
   my $links  = [ f_link 'event', $href, $_create_action->( $req ) ];

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(rota_manager) {
   my ($self, $req) = @_;

   my $moniker  =  $self->moniker;
   my $params   =  $req->query_params->( { optional => TRUE } );
   my $type     =  $params->{type};
   my $private  =  $params->{private} || FALSE;
   my $service  =  $params->{service} || FALSE;
   my $opts     =  { page    => $params->{page} // 1,
                     private => $private,
                     rows    => $req->session->rows_per_page,
                     service => $service,
                     type    => $type };
   my $rs       =  $self->schema->resultset( 'Vehicle' );
   my $vehicles =  $rs->search_for_vehicles( $opts );
   my $form     =  blank_form;
   my $page     =  {
      forms     => [ $form ],
      selected  => $_select_nav_link_name->( $opts ),
      title     => $_vehicle_title->( $req, $type, $private, $service ), };
   my $links    =  $self->$_vehicles_ops_links( $req, $opts, $vehicles->pager );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, {
      headers => $_vehicles_headers->( $req, $service ) };

   p_row $table, [ map { $self->$_vehicle_links( $req, $service, $_ ) }
                   $vehicles->all ];

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Vehicle - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Vehicle;
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
