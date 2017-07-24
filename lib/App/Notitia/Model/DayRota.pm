package App::Notitia::Model::DayRota;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( C_DIALOG FALSE NUL SPC
                                SHIFT_TYPE_ENUM TILDE TRUE );
use App::Notitia::DOM       qw( new_container p_button p_checkbox p_hidden
                                p_js p_link p_select );
use App::Notitia::Util      qw( assign_link dialog_anchor find_slot
                                js_submit_config js_togglers_config local_dt
                                locm make_tip now_dt register_action_paths
                                slot_claimed slot_identifier slot_limit_index
                                to_dt to_msg );
use Class::Usul::Functions  qw( create_token is_member throw );
use Class::Usul::Time       qw( time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(App::Notitia::Role::DatePicker);

# Public attributes
has '+moniker' => default => 'day';

register_action_paths
   'day/day_rota' => 'day-rota',
   'day/operator_vehicle' => 'operator-vehicle',
   'day/slot' => 'slot';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );
   my $name  = $req->uri_params->( 0, { optional => TRUE } ) // 'main';

   $stash->{page}->{location} = 'schedule';
   $stash->{navigation}
      = $self->rota_navigation_links( $req, $stash->{page}, 'month', $name );

   return $stash;
};

# Private class attributes
my $_max_rota_cols = 5;

# Private functions
my $_add_js_dialog = sub {
   my ($req, $page, $args, $action, $name, $title) = @_;

   my $actionp = $page->{moniker}.'/slot';
   my $href = $req->uri_for_action( $actionp, $args, { action => $action } );

   p_js $page, dialog_anchor $args->[ 2 ], $href, {
      name  => "${action}-${name}",
      title => locm $req, (ucfirst $action).SPC.$title, };

   return;
};

my $_day_label = sub {
   my $v    = locm $_[ 0 ], 'day_rota_heading_'.$_[ 1 ];
   my $span = { 0 => 1, 1 => 2, 2 => 1, 3 => 1, 4 => 1 }->{ $_[ 1 ] };

   return { colspan => $span, value => $v };
};

my $_day_rota_headers = sub {
   return [ map {  $_day_label->( $_[ 0 ], $_ ) } 0 .. $_max_rota_cols - 1 ];
};

my $_onclick_relocate = sub {
   my ($page, $k, $href) = @_;

   p_js $page, js_submit_config $k, 'click', 'location', [ "${href}" ];

   return;
};

my $_operators_region = sub {
   my ($req, $page, $data, $k) = @_; my $region;

   exists $data->{ $k }->{operator}
      and $region = $data->{ $k }->{operator}->region;

   return { class => 'narrow', value => $region // NUL };
};

my $_operators_vehicle_label = sub {
   my $slov = shift; $slov or return 'N';

   return $slov->type eq '4x4' ? $slov->type
        : $slov->type eq 'car' ? ucfirst( $slov->type )
        : 'N';
};

my $_operators_vehicle_link = sub {
   my ($req, $page, $data, $k) = @_;

   my $slot_data = $data->{ $k };
   my $vehicle_link = { class => 'narrow', value => NUL };

   $slot_data->{rota_dt} or return $vehicle_link;

   my $actionp = $page->{moniker}.'/operator_vehicle';
   my $local_rota_dt = local_dt $slot_data->{rota_dt};
   my $args = [ $slot_data->{rota_name}, $local_rota_dt->ymd, $k ];
   my $tip = locm $req, 'operators_vehicle_tip';
   my $id = "${k}_vehicle";

   if ($slot_data->{operator} eq $req->username and not $page->{disabled}) {
      p_link $vehicle_link, $id, '#', {
         class => 'windows', request => $req, tip => $tip,
         value => $_operators_vehicle_label->( $slot_data->{slov} ),
      };

      p_js $page, dialog_anchor $id, $req->uri_for_action( $actionp, $args ), {
         name => 'operator-vehicle' ,
         title => locm $req, 'operators_vehicle_title' };
   }
   else {
      $vehicle_link->{value}
         = $_operators_vehicle_label->( $slot_data->{slov} );
   }

   return $vehicle_link;
};

my $_participents_link = sub {
   my ($req, $page, $event) = @_; $event or return;

   my $href = $req->uri_for_action( 'event/participents', [ $event->uri ] );
   my $tip  = locm $req, 'participents_view_link', $event->label;

   return { class   => 'narrow',
            colspan => 1,
            value   => { class => 'list-icon', hint => locm( $req, 'Hint' ),
                         href  => $href,       name => 'view-participents',
                         tip   => $tip,        type => 'link',
                         value => '&nbsp;', } };
};

my $_push_slot_claim_js = sub {
   my $page = shift;
   my $id   = substr create_token, 0, 5;
   my $assignee_id = "assignee_${id}";
   my $args = [ "${assignee_id}_label" ];

   p_js $page, js_togglers_config $assignee_id, 'change', 'hide', $args;

   return $assignee_id;
};

my $_slot_contact_info = sub {
   my ($req, $slot) = @_; slot_claimed $slot or return NUL;

   for my $role ('controller', 'rota_manager') {
      is_member $role, $req->session->roles
         and return "(\x{260E} ".$slot->{operator}->mobile_phone.')';
   }

   return NUL;
};

my $_slot_label = sub {
   return slot_claimed( $_[ 1 ] ) ? $_[ 1 ]->{operator}->label
                                  : locm $_[ 0 ], 'Vacant';
};

my $_slot_link = sub {
   my ($req, $page, $data, $k, $slot_type) = @_;

   my $value = $_slot_label->( $req, $data->{ $k } );

   $page->{disabled} and return { colspan => 2, value => $value };

   my $action = slot_claimed( $data->{ $k } ) ? 'yield' : 'claim';
   my $operator = $data->{ $k }->{operator} // NUL;
   my $can_yield = ($operator eq $req->username
                    or is_member 'rota_manager', $req->session->roles)
                 ? TRUE : FALSE;

   $action eq 'yield' and not $can_yield
      and return { colspan => 2, value => $value };

   my $opts = { action => $action,
                args => [ $slot_type,
                          $_slot_contact_info->( $req, $data->{ $k } ) ],
                name => $k, request => $req, value => $value };
   my $link = { colspan => 2, }; p_link $link, 'slot', C_DIALOG, $opts;

   return $link;
};

my $_summary_link = sub {
   my $opts = shift; my $class = 'vehicle-not-needed'; my $value = NUL;

   $opts or return { class => $class, value => '&nbsp;' x 2 };

   if    ($opts->{vehicle    }) { $value = 'V'; $class = 'vehicle-assigned'  }
   elsif ($opts->{vehicle_req}) { $value = 'R'; $class = 'vehicle-requested' }

   return { class => $class, value => $value };
};

my $_vreqs_for_event = sub {
   my ($schema, $event) = @_;

   my $tport_rs = $schema->resultset( 'Transport' );
   my $assigned = $tport_rs->assigned_vehicle_count( $event->id );
   my $vreq_rs  = $schema->resultset( 'VehicleRequest' );
   my $vreqs    = $vreq_rs->search( { event_id => $event->id } );

   $vreqs->count or return FALSE;

   my $requested = $vreqs->get_column( 'quantity' )->sum;

   return { vehicle     => ($assigned == $requested ? TRUE : FALSE),
            vehicle_req => TRUE };
};

my $_vehicle_request_link = sub {
   my ($req, $page, $schema, $event) = @_; $event or return;

   my $actionp = 'asset/request_vehicle';
   my $href    = $req->uri_for_action( $actionp, [ $event->uri ] );
   my $link    = { class => 'align-center embeded small-slot tips' };
   my $tip     = locm $req, 'vehicle_request_tip', $event->label;
   my $hint    = locm $req, 'Event Assignment';
   my $vreqs   = $_vreqs_for_event->( $schema, $event );
   my $summary = $_summary_link->( $vreqs );

   $link->{title} = $hint.SPC.TILDE.SPC.$tip;
   $link->{value} = { class => $summary->{class}.' rota-link',
                      href  => $href,
                      name  => 'view-vehicle-requests',
                      type  => 'link',
                      value => $summary->{value}, };

   return $link;
};

my $_controllers = sub {
   my ($req, $page, $rota_name, $local_dt, $data, $limits) = @_;

   my $rota = $page->{rota}; my $controls = $rota->{controllers};

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $max_slots = $limits->[ slot_limit_index $shift_type, 'controller' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_controller_${subslot}";
         my $action = slot_claimed( $data->{ $k } ) ? 'yield' : 'claim';
         my $date   = $local_dt->clone->truncate( to => 'day' );
         my $args   = [ $rota_name, $date->ymd, $k ];
         my $link   = $_slot_link->( $req, $page, $data, $k, 'controller' );

         push @{ $controls },
            [ { class => 'rota-header', value   => locm( $req, $k ), },
              { class => 'centre',      colspan => $_max_rota_cols,
                value => $link->{value} } ];

         $_add_js_dialog->( $req, $page, $args, $action,
                            'controller-slot', 'Controller Slot' );
      }
   }

   return;
};

my $_driver_row = sub {
   my ($req, $page, $args, $data) = @_; my $k = $args->[ 2 ];

   return [ { value => locm( $req, $k ), class => 'rota-header' },
            $_slot_link->( $req, $page, $data, $k, 'driver' ),
            $_operators_region->( $req, $page, $data, $k ),
            $_operators_vehicle_link->( $req, $page, $data, $k ),
            assign_link( $req, $page, $args, $data->{ $k } ),
            ];
};

my $_event_link = sub {
   my ($req, $page, $local_dt, $event) = @_;

   unless ($event) {
      my $name   = 'create-event';
      my $class  = 'blank-event submit';
      my $params = { date => $local_dt->ymd };
      my $href   = $req->uri_for_action( 'event/event', [], $params );

      $_onclick_relocate->( $page, $name, $href );

      return { class => $class, colspan => $_max_rota_cols, name => $name, };
   }

   my $href = $req->uri_for_action( 'event/event_summary', [ $event->uri ] );
   my $tip  = locm $req, 'Click to view the [_1] event',
      ucfirst $event->localised_label( $req );

   return {
      colspan  => $_max_rota_cols - 2,
      value    => {
         class => 'table-link', hint => locm( $req, 'Hint' ),
         href  => $href,        name => $event->name,
         tip   => $tip,         type => 'link',
         value => ucfirst locm $req, lc $event->name, }, };
};

my $_events = sub {
   my ($self, $req, $page, $name, $local_dt, $schema, $todays_events) = @_;

   my $href    = $req->uri_for_action( $page->{moniker}.'/day_rota' );
   my $picker  = $self->date_picker
      ( $req, 'rota-date-form', $name, $local_dt, $href );
   my $col1    = { value => $picker, class => 'rota-date' };
   my $first   = TRUE;

   while (defined (my $event = $todays_events->next) or $first) {
      my $col2 = $_vehicle_request_link->( $req, $page, $schema, $event );
      my $col3 = $_event_link->( $req, $page, $local_dt, $event );
      my $col4 = $_participents_link->( $req, $page, $event );
      my $cols = [ $col1, $col2, $col3 ];

      $col4 and push @{ $cols }, $col4;
      push @{ $page->{rota}->{events} }, $cols;
      $col1 = { value => undef }; $first = FALSE;
   }

   $self->date_picker_js( $page );
   return;
};

my $_rider_row = sub {
   my ($req, $page, $args, $data) = @_; my $k = $args->[ 2 ];

   return [ { value => locm( $req, $k ), class => 'rota-header' },
            $_slot_link->( $req, $page, $data, $k, 'rider' ),
            $_operators_region->( $req, $page, $data, $k ),
            $_operators_vehicle_link->( $req, $page, $data, $k ),
            assign_link( $req, $page, $args, $data->{ $k } ),
            ];
};

my $_riders_n_drivers = sub {
   my ($req, $page, $rota_name, $local_dt, $data, $limits) = @_;

   my $shift_no = 0;

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $shift     = $page->{rota}->{shifts}->[ $shift_no++ ] = {};
      my $riders    = $shift->{riders } = [];
      my $drivers   = $shift->{drivers} = [];
      my $max_slots = $limits->[ slot_limit_index $shift_type, 'rider' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_rider_${subslot}";
         my $action = slot_claimed( $data->{ $k } ) ? 'yield' : 'claim';
         my $date   = $local_dt->clone->truncate( to => 'day' );
         my $args   = [ $rota_name, $date->ymd, $k ];

         push @{ $riders }, $_rider_row->( $req, $page, $args, $data );
         $_add_js_dialog->( $req, $page, $args, $action,
                            'rider-slot', 'Rider Slot' );
      }

      $max_slots = $limits->[ slot_limit_index $shift_type, 'driver' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_driver_${subslot}";
         my $action = slot_claimed( $data->{ $k } ) ? 'yield' : 'claim';
         my $date   = $local_dt->clone->truncate( to => 'day' );
         my $args   = [ $rota_name, $date->ymd, $k ];

         push @{ $drivers }, $_driver_row->( $req, $page, $args, $data );
         $_add_js_dialog->( $req, $page, $args, $action,
                            'driver-slot', 'Driver Slot' );
      }
   }

   return;
};

# Private methods
my $_day_page = sub {
   my ($self, $req, $name, $rota_dt, $todays_events, $data) = @_;

   my $local_dt =  local_dt $rota_dt;
   my $actionp  =  $self->moniker.'/day_rota';
   my $args     =  [ $name, $local_dt->clone->add( days => 1 )->ymd ];
   my $next     =  $req->uri_for_action( $actionp, $args );
      $args     =  [ $name, $local_dt->clone->subtract( days => 1 )->ymd ];
   my $prev     =  $req->uri_for_action( $actionp, $args );
   my $sod      =  local_dt( now_dt )->truncate( to => 'day' );
   my $date     =  $local_dt->month_name.SPC.$local_dt->day.SPC.$local_dt->year;
   my $page     =  {
      disabled  => $local_dt < $sod ? TRUE : FALSE,
      fields    => { nav => { next => $next, prev => $prev }, },
      moniker   => $self->moniker,
      rota      => { controllers => [],
                     events      => [],
                     headers     => $_day_rota_headers->( $req ),
                     shifts      => [], },
      template  => [ '/menu', 'custom/day-table' ],
      title     => locm $req, 'day_rota_title', locm( $req, $name ), $date };
   my $limits   =  $self->config->slot_limits;
   my $schema   =  $self->schema;

   $self->$_events( $req, $page, $name, $local_dt, $schema, $todays_events );
   $_controllers->( $req, $page, $name, $local_dt, $data, $limits );
   $_riders_n_drivers->( $req, $page, $name, $local_dt, $data, $limits );

   return $page;
};

my $_find_by_shortcode = sub {
   my ($self, $scode) = @_; my $rs = $self->schema->resultset( 'Person' );

   return $rs->find_by_shortcode( $scode );
};

my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

my $_push_vehicle_select = sub {
   my ($self, $req, $form, $id, $person, $args) = @_;

   my $rota_dt = to_dt $args->[ 1 ];
   my $slot = find_slot $person, $args->[ 0 ], $rota_dt, $args->[ 2 ];
   my $vehicle_id = $slot ? $slot->operator_vehicle_id : undef;
   my $vehicle_rs = $self->schema->resultset( 'Vehicle' );
   my $vehicle = $vehicle_id ? $vehicle_rs->find( $vehicle_id ) : NUL;
   my $vehicles = $vehicle_rs->list_vehicles( {
      fields => { selected => $vehicle }, owner => $person } );

   p_select $form, 'vehicle', [ [ NUL, undef ], @{ $vehicles } ], {
      container_class => 'dialog-contrast', label => 'personal_vehicle',
      label_id => "${id}_label", tip => make_tip $req, 'personal_vehicle_tip' };

   p_hidden $form, 'original_vehicle', $vehicle;

   return;
};

# Public methods
sub claim_slot_action : Role(rota_manager) Role(rider) Role(controller)
                        Role(driver) {
   my ($self, $req) = @_;

   my $params     = $req->uri_params;
   my $rota_name  = $params->( 0 );
   my $rota_date  = $params->( 1 );
   my $name       = $params->( 2 );
   my $rota_dt    = to_dt( $rota_date );
   my $opts       = { optional => TRUE };
   my $assigner   = $req->username;
   my $assignee   = $req->body_params->( 'assignee', $opts ) || $assigner;
   my $person     = $self->$_find_by_shortcode( $assignee );
   my $request_sv = $req->body_params->( 'request_service_vehicle', $opts );
   my $vrn        = $req->body_params->( 'vehicle', $opts );
   my $vehicle_rs = $self->schema->resultset( 'Vehicle' );
   my $vehicle    = $vrn ? $vehicle_rs->find_vehicle_by( $vrn ) : undef;

   $request_sv //= FALSE;
   $vehicle and ($vehicle->owner_id == $person->id or $vehicle = undef);

   $person->claim_slot
      ( $rota_name, $rota_dt, $name, $request_sv, $vehicle, $assigner );

   $self->send_event( $req, "action:slot-claim shortcode:${assignee} "
                          . "rota_name:${rota_name} rota_date:${rota_date} "
                          . "slot:${name} vehicle_requested:${request_sv}" );

   my $args     = [ $rota_name, $rota_date ];
#   my $location = $req->uri_for_action( $self->moniker.'/day_rota', $args );
   my $sr_map   = $self->config->slot_region;
   my $label    = slot_identifier $rota_name, $rota_date, $name, $sr_map;
   my $message  = [ to_msg '[_1] claimed slot [_2]', $person->label, $label ];

   return { redirect => { message => $message } };
}

sub day_rota : Role(any) {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $today     = time2str '%Y-%m-%d';
   my $name      = $params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $params->( 1, { optional => TRUE } ) // $today;
   my $rota_dt   = to_dt $rota_date;
   my $type_id   = $self->$_find_rota_type( $name )->id;
   my $slot_rs   = $self->schema->resultset( 'Slot' );
   my $event_rs  = $self->schema->resultset( 'Event' );
   my $events    = $event_rs->search_for_a_days_events
      ( $type_id, $rota_dt, { event_type => [ qw( person training ) ] } );
   my $opts      = { rota_type => $type_id, on => $rota_dt };
   my $slot_data = {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $vehicle_type = $slot->type_name eq 'driver' ? [ '4x4', 'car' ]
                       : $slot->type_name eq 'rider'  ? 'bike' : undef;

      $slot_data->{ $slot->key } =
         { name        => $slot->key,
           operator    => $slot->operator,
           rota_dt     => $rota_dt,
           rota_name   => $name,
           slov        => $slot->operator_vehicle,
           type        => $vehicle_type,
           vehicle     => $slot->vehicle,
           vehicle_req => $slot->vehicle_requested };
   }

   my $page = $self->$_day_page( $req, $name, $rota_dt, $events, $slot_data );

   return $self->get_stash( $req, $page );
}

sub day_selector_action : Role(any) {
   my ($self, $req) = @_;

   return $self->date_picker_redirect( $req, $self->moniker.'/day_rota' );
}

sub operator_vehicle : Dialog Role(any) {
   my ($self, $req) = @_;

   my $rota_name = $req->uri_params->( 0 );
   my $rota_date = $req->uri_params->( 1 );
   my $slot_key  = $req->uri_params->( 2 );
   my $stash     = $self->dialog_stash( $req );
   my $person    = $self->$_find_by_shortcode( $req->username );
   my $actionp   = $self->moniker.'/operator_vehicle';
   my $args      = [ $rota_name, $rota_date, $slot_key, $person ];
   my $href      = $req->uri_for_action( $actionp, $args );
   my $form      = $stash->{page}->{forms}->[ 0 ]
                 = new_container 'operator-vehicle', $href;
   my $id        = 'vehicle';

   $self->$_push_vehicle_select( $req, $form, $id, $person, $args );

   p_button $form, 'select_operator_vehicle', 'select_operator_vehicle', {
      class => 'button', container_class => 'right-last',
      tip => make_tip $req, 'select_operator_vehicle_tip' };

   return $stash;
}

sub select_operator_vehicle_action : Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $rota_name  = $req->uri_params->( 0 );
   my $rota_date  = $req->uri_params->( 1 );
   my $slot_key   = $req->uri_params->( 2 );
   my $scode      = $req->uri_params->( 3 );
   my $rota_dt    = to_dt $rota_date;
   my @slot_key   = split m{ _ }mx, $slot_key;
   my $opts       = { optional => TRUE };
   my $vehicle_rs = $self->schema->resultset( 'Vehicle' );

   $scode ne $req->username
      and throw 'Updating selected vehicles for other people is not allowed';

   if (my $vrn = $req->body_params->( 'vehicle', $opts )) {
      my $vehicle = $vehicle_rs->find_vehicle_by( $vrn );

      $vehicle->assign_private( $rota_name, $rota_dt, @slot_key );
   }
   elsif (my $original = $req->body_params->( 'original_vehicle', $opts )) {
      my $vehicle = $vehicle_rs->find_vehicle_by( $original );

      $vehicle->unassign_private( $rota_name, $rota_dt, @slot_key );
   }

   my $message = [ to_msg 'Selected vehicle updated' ];

   return { redirect => { message => $message } }; # location referer
}

sub slot : Dialog Role(rota_manager) Role(rider) Role(controller) Role(driver) {
   my ($self, $req) = @_;

   my $params = $req->uri_params;
   my $name   = $params->( 2 );
   my $args   = [ $params->( 0 ), $params->( 1 ), $name ];
   my $action = $req->query_params->( 'action' ); # claim or yield
   my $stash  = $self->dialog_stash( $req );
   my $href   = $req->uri_for_action( $self->moniker.'/slot', $args );
   my $form   = $stash->{page}->{forms}->[ 0 ]
              = new_container "${action}-slot", $href;
   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   if ($action eq 'claim') {
      my $person = $self->$_find_by_shortcode( $req->username );
      my $id = 'vehicle';

      if ($slot_type and is_member 'rota_manager', $req->session->roles) {
         my $opts = { fields => { selected => $person } };
         my $person_rs = $self->schema->resultset( 'Person' );
         my $people = $person_rs->list_people( $slot_type, $opts );

         $id = $_push_slot_claim_js->( $stash->{page} );
         p_select $form, 'assignee', [ [ NUL, undef ], @{ $people } ], {
            class => 'standard-field togglers', id => $id };
      }

      if ($slot_type eq 'driver' or $slot_type eq 'rider') {
         $self->$_push_vehicle_select( $req, $form, $id, $person, $args );

         p_checkbox $form, 'request_service_vehicle', TRUE, { checked => TRUE };
      }
   }

   p_button $form, 'confirm', "${action}_slot", {
      class => 'button', container_class => 'right-last',
      tip => make_tip $req, "${action}_slot_tip", [ $slot_type ] };

   return $stash;
}

sub slot_link {
   my $self = shift; return $_slot_link->( @_ );
}

sub yield_slot_action : Role(rota_manager) Role(rider) Role(controller)
                        Role(driver) {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $slot_name = $params->( 2 );
   my $rota_dt   = to_dt $rota_date;
   my $user      = $self->$_find_by_shortcode( $req->username );
   my $slot      = find_slot $user, $rota_name, $rota_dt, $slot_name;
   my $assignee  = $self->$_find_by_shortcode( $slot->operator );

   $user->yield_slot( $rota_name, $rota_dt, $slot_name );

   $self->send_event( $req, "action:slot-yield shortcode:${assignee} "
                          . "rota_name:${rota_name} rota_date:${rota_date} "
                          . "slot:${slot_name}" );

   my $args     = [ $rota_name, $rota_date ];
#   my $location = $req->uri_for_action( $self->moniker.'/day_rota', $args );
   my $sr_map   = $self->config->slot_region;
   my $label    = slot_identifier $rota_name, $rota_date, $slot_name, $sr_map;
   my $message  = [ to_msg '[_1] yielded slot [_2]', $assignee->label, $label ];

   return { redirect => { message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::DayRota - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::DayRota;
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

Copyright (c) 2017 Peter Flanigan. All rights reserved

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
