package App::Notitia::Model::Schedule;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SHIFT_TYPE_ENUM
                                SPC TRUE );
use App::Notitia::Util      qw( assign_link bind button dialog_anchor
                                display_duration js_submit_config
                                js_window_config lcm_for loc
                                register_action_paths set_element_focus
                                slot_claimed slot_identifier
                                slot_limit_index table_link to_dt to_msg
                                uri_for_action );
use Class::Usul::Functions  qw( is_member sum throw );
use Class::Usul::Time       qw( time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'sched';

register_action_paths
   'sched/assign_summary' => 'assignment-summary',
   'sched/day_rota'       => 'day-rota',
   'sched/month_rota'     => 'month-rota',
   'sched/slot'           => 'slot',
   'sched/week_rota'      => 'week-rota';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );
   my $name  = $req->uri_params->( 0, { optional => TRUE } ) // 'main';

   $stash->{nav}->{list} = $self->rota_navigation_links( $req, 'month', $name );
   $stash->{page}->{location} = 'schedule';

   return $stash;
};

# Private class attributes
my $_rota_types_id = {};
my $_max_rota_cols = 4;

# Private functions
my $_add_js_dialog = sub {
   my ($req, $page, $args, $action, $name, $title) = @_;

   $name = "${action}-${name}"; $title = loc $req, (ucfirst $action).SPC.$title;

   my $path = $page->{moniker}.'/slot';
   my $href = uri_for_action $req, $path, $args, { action => $action };
   my $js   = $page->{literal_js} //= [];

   push @{ $js }, dialog_anchor( $args->[ 2 ], $href, {
      name => $name, title => $title, useIcon => \1 } );

   return;
};

my $_async_event_tip = sub {
   my ($req, $page, $tport) = @_;

   my $uri  = $tport->event->uri;
   my $href = uri_for_action $req, 'event/event_info', [ $uri ];

   push @{ $page->{literal_js} }, js_window_config
      $uri, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_async_slot_tip = sub {
   my ($req, $page, $moniker, $id) = @_;

   my $name    = $page->{rota}->{name};
   my $actionp = "${moniker}/assign_summary";
   my $href    = uri_for_action $req, $actionp, [ "${name}_${id}" ];

   push @{ $page->{literal_js} }, js_window_config
      $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_async_v_event_tip = sub {
   my ($req, $page, $event) = @_;

   my $href = uri_for_action $req, 'event/vehicle_info', [ $event->uri ];

   push @{ $page->{literal_js} }, js_window_config
      $event->uri, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_async_vreq_tip = sub {
   my ($req, $page, $event) = @_;

   my $actionp = 'asset/request_info';
   my $href    = uri_for_action $req, $actionp, [ $event->uri ];
   my $id      = 'request-'.$event->uri;

   push @{ $page->{literal_js} }, js_window_config
      $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_confirm_slot_button = sub {
   return button $_[ 0 ],
      { class =>  'right-last', label => 'confirm', value => $_[ 1 ].'_slot' };
};

my $_day_label = sub {
   my $v    = loc $_[ 0 ], 'day_rota_heading_'.$_[ 1 ];
   my $span = { 0 => 1, 1 => 1, 2 => 2, 3 => 1 }->{ $_[ 1 ] };

   return { colspan => $span, value => $v };
};

my $_day_rota_headers = sub {
   return [ map {  $_day_label->( $_[ 0 ], $_ ) } 0 .. $_max_rota_cols - 1 ];
};

my $_date_picker = sub {
   my ($name, $local_dt, $href) = @_;

   return { class       => 'rota-date-form',
            content     => {
               list     => [ {
                  name  => 'rota_name',
                  type  => 'hidden',
                  value => $name,
               }, {
                  class => 'rota-date-field shadow submit',
                  label => NUL,
                  name  => 'rota_date',
                  type  => 'date',
                  value => $local_dt->ymd,
               }, {
                  class => 'rota-date-field',
                  disabled => TRUE,
                  name  => 'rota_date_display',
                  label => NUL,
                  type  => 'textfield',
                  value => $local_dt->day_abbr.SPC.$local_dt->day,
               }, ],
               type     => 'list', },
            form_name   => 'day-rota',
            href        => $href,
            type        => 'form', };
};

my $_local_dt = sub {
   return $_[ 0 ]->clone->set_time_zone( 'local' );
};

my $_is_this_month = sub {
   my ($rno, $local_dt) = @_; $rno > 0 and return TRUE;

   return $local_dt->day < 15 ? TRUE : FALSE;
};

my $_month_label = sub {
   return { class => 'day-of-week',
            value => loc( $_[ 0 ], 'month_rota_heading_'.$_[ 1 ] ) };
};

my $_month_rota_headers = sub {
   return [ map {  $_month_label->( $_[ 0 ], $_ ) } 0 .. 6 ];
};

my $_month_rota_max_slots = sub {
   my $limits = shift;

   return [ sum( map { $limits->[ slot_limit_index $_, 'controller' ] }
                    @{ SHIFT_TYPE_ENUM() } ),
            sum( map { $limits->[ slot_limit_index 'day', $_ ] }
                       'rider', 'driver' ),
            sum( map { $limits->[ slot_limit_index 'night', $_ ] }
                       'rider', 'driver' ), ];
};

my $_month_rota_title = sub {
   my ($req, $rota_name, $date) = @_; $date = $_local_dt->( $date );

   my $title = ucfirst( loc( $req, $rota_name ) ).SPC
             . loc( $req, 'rota for' ).SPC.$date->month_name.SPC
             . $date->year;

   return $title;
};

my $_next_month = sub {
   my ($req, $actionp, $rota_name, $date) = @_;

   $date = $_local_dt->( $date )->truncate( to => 'day' )
                                  ->set( day => 1 )->add( months => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_onchange_submit = sub {
   return js_submit_config 'rota_date', 'change', 'submitForm',
                         [ 'rota_redirect', 'day-rota' ];
};

my $_onclick_relocate = sub {
   my ($page, $k, $href) = @_;

   push @{ $page->{literal_js} },
      js_submit_config $k, 'click', 'location', [ "${href}" ];

   return;
};

my $_operators_vehicle = sub {
   my ($slot, $cache) = @_; $slot->operator->id or return NUL;

   exists $cache->{ $slot->operator->id }
      and return $cache->{ $slot->operator->id };

   my $pv      = ($slot->operator_vehicles->all)[ 0 ];
   my $pv_type = $pv ? $pv->type : NUL;
   my $label   = $pv_type eq '4x4' ? $pv_type
               : $pv_type eq 'car' ? ucfirst( $pv_type ) : undef;

   return $cache->{ $slot->operator->id } = $label;
};

my $_prev_month = sub {
   my ($req, $actionp, $rota_name, $date) = @_;

   $date = $_local_dt->( $date )->truncate( to => 'day' )
                                  ->set( day => 1 )->subtract( months => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_slot_label = sub {
   return slot_claimed( $_[ 1 ] ) ? $_[ 1 ]->{operator}->label
                                  : loc( $_[ 0 ], 'Vacant' );
};

my $_summary_link = sub {
   my ($req, $type, $span, $id, $opts) = @_;

   $opts or return { colspan => $span, value => '&nbsp;' x 2 };

   my $value = NUL; my $class = 'vehicle-not-needed';

   if    ($opts->{vehicle    }) { $value = 'V'; $class = 'vehicle-assigned'  }
   elsif ($opts->{vehicle_req}) { $value = 'V'; $class = 'vehicle-requested' }

   my $title = loc $req, (ucfirst $type).' Assignment';

   $class .= ' windows tips';

   return { class => $class, colspan => $span, name => $id,
            title => $title, value   => $value };
};

my $_event_link = sub {
   my ($req, $page, $local_dt, $event) = @_;

   unless ($event) {
      my $name  = 'create-event';
      my $class = 'blank-event submit';
      my $href  =
         uri_for_action $req, 'event/event', [], { date => $local_dt->ymd };

      $_onclick_relocate->( $page, $name, $href );

      return { class => $class, colspan => $_max_rota_cols, name => $name, };
   }

   my $href = uri_for_action $req, 'event/event_summary', [ $event->uri ];
   my $tip  = loc $req, 'Click to view the [_1] event', [ $event->label ];

   return {
      colspan  => $_max_rota_cols - 2,
      value    => {
         class => 'table-link', hint => loc( $req, 'Hint' ),
         href  => $href,        name => $event->name,
         tip   => $tip,         type => 'link',
         value => $event->name, }, };
};

my $_participents_link = sub {
   my ($req, $page, $event) = @_; $event or return;

   my $href  = uri_for_action $req, 'event/participents', [ $event->uri ];
   my $tip   = loc $req, 'participents_view_link', [ $event->label ];

   return { class   => 'narrow',
            colspan => 1,
            value   => { class => 'list-icon', hint => loc( $req, 'Hint' ),
                         href  => $href,       name => 'view-participents',
                         tip   => $tip,        type => 'link',
                         value => '&nbsp;', } };
};

my $_slot_link = sub {
   my ($req, $page, $data, $k, $slot_type) = @_;

   my $claimed = slot_claimed $data->{ $k };
   my $value   = $_slot_label->( $req, $data->{ $k } );
   my $tip     = loc( $req, ($claimed ? 'yield_slot_tip' : 'claim_slot_tip'),
                      $slot_type );

   return { colspan => 2, value => table_link( $req, $k, $value, $tip ) };
};

my $_vreq_state = sub {
   my ($n_assigned, $vreqs) = @_;

   my $n_requested = $vreqs->get_column( 'quantity' )->sum;

   return { vehicle     => ($n_assigned == $n_requested ? TRUE : FALSE),
            vehicle_req => TRUE };
};

my $_vehicle_request_link = sub {
   my ($schema, $req, $page, $event) = @_; $event or return;

   my $name     = 'view-vehicle-requests';
   my $href     = uri_for_action $req, 'asset/request_vehicle', [ $event->uri ];
   my $tip      = loc $req, 'vehicle_request_link', [ $event->label ];
   my $tport_rs = $schema->resultset( 'Transport' );
   my $assigned = $tport_rs->assigned_vehicle_count( $event->id );
   my $vreq_rs  = $schema->resultset( 'VehicleRequest' );
   my $vreqs    = $vreq_rs->search( { event_id => $event->id } );
   my $opts     = $vreqs->count ? $_vreq_state->( $assigned, $vreqs ) : FALSE;
   my $link     = $_summary_link->( $req, 'event', 1, $name, $opts );

   $link->{class} .= ' small-slot';
   $link->{value}  = { hint  => loc( $req, 'Hint' ), href  => $href,
                       name  => $name,               tip   => $tip,
                       type  => 'link',              value => $link->{value}, };

   return $link;
};

my $_week_label = sub {
   my ($req, $date, $cno) = @_;

   my $local_dt = $_local_dt->( $date )->add( days => $cno );
   my $key      = 'week_rota_heading_'.(lc $local_dt->day_abbr);
   my $v        = loc $req, $key, to_msg $local_dt->day;

   return { class => 'day-of-week', value => $v };
};

my $_week_rota_headers = sub {
   my ($req, $date) = @_;

   return [     { class => '', value => 'vehicle', },
            map {  $_week_label->( $req, $date, $_ ) } 0 .. 6 ];
};

my $_week_rota_title = sub {
   my ($req, $rota_name, $date) = @_; my $local_dt = $_local_dt->( $date );

   return ucfirst( loc( $req, $rota_name ) ).SPC
        . loc( $req, 'rota commencing' ).SPC
        . $local_dt->day.SPC.$local_dt->month_name.SPC.$local_dt->year;
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
         my $link   = $_slot_link->( $req, $page, $data, $k, 'controller');

         push @{ $controls },
            [ { class => 'rota-header', value   => loc( $req, $k ), },
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

   return [ { value => loc( $req, $k ), class => 'rota-header' },
            { value => undef },
            $_slot_link->( $req, $page, $data, $k, 'driver' ),
            { value => $data->{ $k }->{ops_veh}, class => 'narrow' }, ];
};

my $_events = sub {
   my ($schema, $req, $page, $name, $local_dt, $todays_events) = @_;

   my $href    = uri_for_action $req, $page->{moniker}.'/day_rota';
   my $picker  = $_date_picker->( $name, $local_dt, $href );
   my $col1    = { value => $picker, class => 'rota-date narrow' };
   my $first   = TRUE;

   while (defined (my $event = $todays_events->next) or $first) {
      my $col2 = $_vehicle_request_link->( $schema, $req, $page, $event );
      my $col3 = $_event_link->( $req, $page, $local_dt, $event );
      my $col4 = $_participents_link->( $req, $page, $event );
      my $cols = [ $col1, $col2, $col3 ];

      $col4 and push @{ $cols }, $col4;
      push @{ $page->{rota}->{events} }, $cols;
      $col1 = { value => undef }; $first = FALSE;
   }

   push @{ $page->{literal_js} }, $_onchange_submit->();
   return;
};

my $_rider_row = sub {
   my ($req, $page, $args, $data) = @_; my $k = $args->[ 2 ];

   return [ { value => loc( $req, $k ), class => 'rota-header' },
            assign_link( $req, $page, $args, $data->{ $k } ),
            $_slot_link->( $req, $page, $data, $k, 'rider' ),
            { value => $data->{ $k }->{ops_veh}, class => 'narrow' }, ];
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
my $_find_rota_type_id = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] )->id;
};

my $_first_day_of_month = sub {
   my ($self, $req, $date) = @_;

   $date = $_local_dt->( $date )->set( day => 1 );

   $self->update_navigation_date( $req, $date );

   while ($date->day_of_week > 1) { $date = $date->subtract( days => 1 ) }

   return $date->set_time_zone( 'GMT' );
};

my $_left_shift = sub {
   my ($self, $req, $rota_name, $date) = @_;

   my $actionp = $self->moniker.'/week_rota';

   $date = $_local_dt->( $date )->truncate( to => 'day' )
                                ->subtract( days => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_next_week = sub {
   my ($self, $req, $rota_name, $date) = @_;

   my $actionp = $self->moniker.'/week_rota';

   $date = $_local_dt->( $date )->truncate( to => 'day' )->add( weeks => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_prev_week = sub {
   my ($self, $req, $rota_name, $date) = @_;

   my $actionp =  $self->moniker.'/week_rota';

   $date = $_local_dt->( $date )->truncate( to => 'day' )
                                ->subtract( weeks => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_right_shift = sub {
   my ($self, $req, $rota_name, $date) = @_;

   my $actionp = $self->moniker.'/week_rota';

   $date = $_local_dt->( $date )->truncate( to => 'day' )->add( days => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_summary_cells = sub {
   my ($self, $req, $page, $date, $shift_types, $slot_types, $data, $rno) = @_;

   my $actionp = $self->moniker.'/assign_summary';
   my $limits  = $self->config->slot_limits;
   my $name    = $page->{rota}->{name};
   my $span    = $page->{rota}->{lcm } / $page->{rota}->{max_slots}->[ $rno ];
   my $cells   = [];

   for my $shift_type (@{ $shift_types }) {
      for my $slot_type (@{ $slot_types }) {
         my $i = slot_limit_index $shift_type, $slot_type;

         for my $slotno (0 .. $limits->[ $i ] - 1) {
            my $key  = "${shift_type}_${slot_type}_${slotno}";
            my $id   = $date->ymd."_${key}";
            my $href = uri_for_action $req, $actionp, [ "${name}_${id}" ];
            my $slot = $data->{ $id };

            push @{ $cells },
               $_summary_link->( $req, $slot_type, $span, $id, $slot );

            $slot and push @{ $page->{literal_js} }, js_window_config
               $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
         }
      }
   }

   return $cells;
};

my $_slot_assignments = sub {
   my ($self, $opts) = @_; $opts = { %{ $opts } }; delete $opts->{event_type};

   my $slot_rs = $self->schema->resultset( 'Slot' ); my $data = {};

   for my $slot ($slot_rs->list_slots_for( $opts )->all) {
      my $k = $_local_dt->( $slot->start_date )->ymd.'_'.$slot->key;

      $data->{ $k } = { name        => $slot->key,
                        operator    => $slot->operator,
                        slot        => $slot,
                        vehicle     => $slot->vehicle,
                        vehicle_req => $slot->bike_requested };
   }

   return $data;
};

my $_rota_summary = sub {
   my ($self, $req, $page, $local_dt, $has_event, $data) = @_;

   my $lcm   = $page->{rota}->{lcm};
   my $name  = $page->{rota}->{name};
   my $table = { class => 'month-rota', rows => [], type => 'table' };
   my $value = $has_event->{ $local_dt->ymd } ? loc( $req, 'Events' ) : NUL;

   push @{ $table->{rows} },
      [ { colspan =>     $lcm / 4, value => $local_dt->day },
        { colspan => 3 * $lcm / 4, value => $value } ];

   push @{ $table->{rows} }, $self->$_summary_cells
      ( $req, $page, $local_dt, [ 'day', 'night' ], [ 'controller' ], $data, 0);

   push @{ $table->{rows} }, $self->$_summary_cells
      ( $req, $page, $local_dt, [ 'day' ], [ 'rider', 'driver' ], $data, 1 );

   push @{ $table->{rows} }, $self->$_summary_cells
      ( $req, $page, $local_dt, [ 'night' ], [ 'rider', 'driver' ], $data, 2 );

   my $actionp = $self->moniker.'/day_rota';
   my $href    = uri_for_action $req, $actionp, [ $name, $local_dt->ymd ];
   my $id      = "${name}_".$local_dt->ymd;

   $_onclick_relocate->( $page, $id, $href );

   return { class => 'month-rota submit', name => $id, value => $table };
};

my $_get_page = sub {
   my ($self, $req, $name, $rota_dt, $todays_events, $data) = @_;

   my $schema   =  $self->schema;
   my $limits   =  $self->config->slot_limits;
   my $local_dt =  $_local_dt->( $rota_dt );
   my $title    =  ucfirst( loc( $req, $name ) ).SPC.loc( $req, 'rota for' ).SPC
                .  $local_dt->month_name.SPC.$local_dt->day.SPC.$local_dt->year;
   my $actionp  =  $self->moniker.'/day_rota';
   my $next     =  uri_for_action $req, $actionp,
                   [ $name, $local_dt->clone->add( days => 1 )->ymd ];
   my $prev     =  uri_for_action $req, $actionp,
                   [ $name, $local_dt->clone->subtract( days => 1 )->ymd ];
   my $page     =  {
      fields    => { nav => { next => $next, prev => $prev }, },
      moniker   => $self->moniker,
      rota      => { controllers => [],
                     events      => [],
                     headers     => $_day_rota_headers->( $req ),
                     shifts      => [], },
      template  => [ 'contents', 'rota', 'rota-table' ],
      title     => $title };

   $_events->( $schema, $req, $page, $name, $local_dt, $todays_events );
   $_controllers->( $req, $page, $name, $local_dt, $data, $limits );
   $_riders_n_drivers->( $req, $page, $name, $local_dt, $data, $limits );

   return $page;
};

my $_week_rota_assignments = sub {
   my ($self, $req, $page, $rota_dt, $tuple, $cache, $tports, $events) = @_;

   my $moniker   = $self->moniker;
   my $rota_name = $page->{rota}->{name};
   my $class     = 'narrow week-rota submit tips windows';
   my $row       = [ { class => 'narrow', value => $tuple->[ 0 ] } ];

   for my $cno (0 .. 6) {
      my $date  = $rota_dt->clone->add( days => $cno );
      my $table = { class => 'week-rota', rows => [], type => 'table' };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => loc( $req, 'Rider Assignment' ),
                    value => loc( $req, $_->[ 1 ]->key ) } ] }
         map  { my $href = uri_for_action $req, "${moniker}/day_rota",
                           [ $rota_name, $_local_dt->( $date )->ymd ];
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { my $id = $_local_dt->( $date )->ymd.'_'.$_->key;
                $_async_slot_tip->( $req, $page, $moniker, $id ); [ $id, $_ ] }
         grep { $_->vehicle->name eq $tuple->[ 1 ]->name }
         grep { $_->bike_requested and $_->vehicle }
             @{ $cache->[ $cno ] };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => loc( $req, 'Event Information' ),
                    value => $_->[ 1 ]->event->name } ] }
         map  { my $href = uri_for_action $req, 'asset/request_vehicle',
                           [ $_->[ 0 ] ];
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { $_async_event_tip->( $req, $page, $_ );
                [ $_->event->uri, $_ ] }
         grep { $_->vehicle->vrn eq $tuple->[ 1 ]->vrn }
         grep { $_->event->start_date eq $date } @{ $tports };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => loc( $req, 'Vechicle Event' ),
                    value => $_->[ 1 ]->name } ] }
         map  { my $href = uri_for_action $req, 'event/vehicle_event',
                           [ $_->[ 1 ]->vehicle->vrn, $_->[ 0 ] ];
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { $_async_v_event_tip->( $req, $page, $_ ); [ $_->uri, $_ ] }
         grep { $_->vehicle->vrn eq $tuple->[ 1 ]->vrn }
         grep { $_->start_date eq $date } @{ $events };

      push @{ $row }, { class => 'narrow embeded', value => $table };
   }

   return $row;
};

my $_week_rota_requests = sub {
   my ($self, $req, $page, $rota_dt, $cache, $slots, $events) = @_;

   my $moniker   = $self->moniker;
   my $rota_name = $page->{rota}->{name};
   my $class     = 'narrow week-rota submit tips windows';
   my $row       = [ { class => 'narrow', value => 'Requests' } ];

   for my $cno (0 .. 6) {
      my $date  = $rota_dt->clone->add( days => $cno );
      my $table = { class => 'week-rota', rows => [], type => 'table' };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => loc( $req, 'Rider Assignment' ),
                    value => loc( $req, $_->[ 1 ]->key ) } ] }
         map  { my $href = uri_for_action $req, "${moniker}/day_rota",
                           [ $rota_name, $_local_dt->( $date )->ymd ];
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { my $id = $_local_dt->( $date )->ymd.'_'.$_->key;
                $_async_slot_tip->( $req, $page, $moniker, $id ); [ $id, $_ ] }
         grep { $_->bike_requested and not $_->vehicle }
         map  { push @{ $cache->[ $cno ] }, $_; $_ }
         grep { $_->date eq $date } @{ $slots };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => 'request-'.$_->[ 0 ],
                    title => loc( $req, 'Vehicle Request' ),
                    value => $_->[ 1 ]->name } ] }
         map  { my $href = uri_for_action $req, 'asset/request_vehicle',
                           [ $_->[ 0 ] ];
                $_onclick_relocate->( $page, 'request-'.$_->[ 0 ], $href ); $_ }
         map  { $_async_vreq_tip->( $req, $page, $_ ); [ $_->uri, $_ ] }
         grep { $_->start_date eq $date } @{ $events };

      push @{ $row }, { class => 'narrow embeded', value => $table };
   }

   return $row;
};

# Public methods
sub assign_summary : Role(any) {
   my ($self, $req) = @_;

   my ($rota_name, $rota_date, $shift_type, $slot_type, $subslot)
                =  split m{ _ }mx, $req->uri_params->( 0 ), 5;
   my $key      =  "${shift_type}_${slot_type}_${subslot}";
   my $rota_dt  =  to_dt $rota_date;
   my $data     =  $self->$_slot_assignments( {
      rota_type => $self->$_find_rota_type_id( $rota_name ),
      on        => $rota_dt } )->{ $_local_dt->( $rota_dt)->ymd.'_'.$key };
   my $stash    =  $self->dialog_stash( $req, 'assign-summary' );
   my $fields   =  $stash->{page}->{fields};
   my $operator =  $data->{operator};

   $fields->{operator} = $operator->label;
   $operator->postcode
      and $fields->{operator} .= ' ('.$operator->outer_postcode.')';
   $data->{vehicle} and $fields->{vehicle} = $data->{vehicle}->label;
   ($fields->{start}, $fields->{end}) = display_duration $req, $data->{slot};

   return $stash;
}

sub claim_slot_action : Role(rota_manager) Role(bike_rider) Role(controller)
                        Role(driver) {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $name      = $params->( 2 );
   my $opts      = { optional => TRUE };
   my $bike      = $req->body_params->( 'request_bike', $opts ) // FALSE;
   my $assignee  = $req->body_params->( 'assignee', $opts ) || $req->username;
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_by_shortcode( $assignee );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   # Without tz will create rota records prev. day @ 23:00 during summer time
   $person->claim_slot( $rota_name, to_dt( $rota_date ), $shift_type,
                        $slot_type, $subslot, $bike );

   my $args     = [ $rota_name, $rota_date ];
   my $location = uri_for_action $req, 'sched/day_rota', $args;
   my $label    = slot_identifier
                     $rota_name, $rota_date, $shift_type, $slot_type, $subslot;
   my $message  = [ 'User [_1] claimed slot [_2]', $person->label, $label ];

   return { redirect => { location => $location, message => $message } };
}

sub day_rota : Role(any) {
   my ($self, $req) = @_; my $vehicle_cache = {};

   my $params    = $req->uri_params;
   my $today     = time2str '%Y-%m-%d';
   my $name      = $params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $params->( 1, { optional => TRUE } ) // $today;
   my $rota_dt   = to_dt $rota_date;
   my $type_id   = $self->$_find_rota_type_id( $name );
   my $opts      = { rota_type => $type_id, on => $rota_dt };
   my $slots     = $self->schema->resultset( 'Slot' )->list_slots_for( $opts );
   my $event_rs  = $self->schema->resultset( 'Event' );
   my $events    = $event_rs->search_for_a_days_events( $type_id, $rota_dt );
   my $slot_data = {};

   for my $slot ($slots->all) {
      $slot_data->{ $slot->key } =
         { name        => $slot->key,
           operator    => $slot->operator,
           ops_veh     => $_operators_vehicle->( $slot, $vehicle_cache ),
           vehicle     => $slot->vehicle,
           vehicle_req => $slot->bike_requested };
   }

   my $page = $self->$_get_page( $req, $name, $rota_dt, $events, $slot_data );

   return $self->get_stash( $req, $page );
}

sub month_rota : Role(any) {
   my ($self, $req) = @_;

   my $params    =  $req->uri_params;
   my $rota_name =  $params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date =  $params->( 1, { optional => TRUE } ) // time2str '%Y-%m-01';
   my $rota_dt   =  to_dt $rota_date;
   my $max_slots =  $_month_rota_max_slots->( $self->config->slot_limits );
   my $actionp   =  $self->moniker.'/month_rota';
   my $page      =  {
      fields     => { nav => {
         next    => $_next_month->( $req, $actionp, $rota_name, $rota_dt ),
         prev    => $_prev_month->( $req, $actionp, $rota_name, $rota_dt ) }, },
      rota       => { headers   => $_month_rota_headers->( $req ),
                      lcm       => lcm_for( 4, @{ $max_slots } ),
                      max_slots => $max_slots,
                      name      => $rota_name,
                      rows      => [] },
      template   => [ 'contents', 'rota', 'month-table' ],
      title      => $_month_rota_title->( $req, $rota_name, $rota_dt ), };
   my $first     =  $self->$_first_day_of_month( $req, $rota_dt );
   my $opts      =  {
      after      => $rota_dt->clone->subtract( days => 1 ),
      before     => $rota_dt->clone->add( days => 31 ),
      rota_type  => $self->$_find_rota_type_id( $rota_name ) };
   my $has_event =  $self->schema->resultset( 'Event' )->has_events_for( $opts);
   my $assigned  =  $self->$_slot_assignments( $opts );

   for my $rno (0 .. 5) {
      my $row = []; my $dayno;

      for my $offset (map { 7 * $rno + $_ } 0 .. 6) {
         my $cell = { class => 'month-rota', value => NUL };
         my $ldt  = $_local_dt->( $first->clone->add( days => $offset ) );

         $dayno = $ldt->day; $rno > 3 and $dayno == 1 and last;
         $_is_this_month->( $rno, $ldt ) and $cell = $self->$_rota_summary
            ( $req, $page, $ldt, $has_event, $assigned );
         push @{ $row }, $cell;
      }

      $row->[ 0 ] and push @{ $page->{rota}->{rows} }, $row;
      $rno > 3 and $dayno == 1 and last;
   }

   return $self->get_stash( $req, $page );
}

sub rota_redirect_action : Role(any) {
   my ($self, $req) = @_;

   my $period    = 'day';
   my $params    = $req->body_params;
   my $rota_name = $params->( 'rota_name' );
   my $local_dt  = to_dt $params->( 'rota_date' ), 'local';
   my $args      = [ $rota_name, $local_dt->ymd ];
   my $location  = uri_for_action $req, $self->moniker."/${period}_rota", $args;
   my $message   = [ $req->session->collect_status_message( $req ) ];

   return { redirect => { location => $location, message => $message } };
}

sub slot : Role(rota_manager) Role(bike_rider) Role(controller) Role(driver) {
   my ($self, $req) = @_;

   my $params = $req->uri_params;
   my $name   = $params->( 2 );
   my $args   = [ $params->( 0 ), $params->( 1 ), $name ];
   my $action = $req->query_params->( 'action' );
   my $stash  = $self->dialog_stash( $req, "${action}-slot" );
   my $page   = $stash->{page};
   my $fields = $page->{fields};

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   if ($action eq 'claim') {
      my $role = $slot_type eq 'controller' ? 'controller'
               : $slot_type eq 'rider'      ? 'bike_rider'
               : $slot_type eq 'driver'     ? 'driver'
                                            : FALSE;

      if ($role and is_member 'rota_manager', $req->session->roles) {
         my $person_rs = $self->schema->resultset( 'Person' );
         my $person    = $person_rs->find_by_shortcode( $req->username );
         my $opts      = { fields => { selected => $person } };
         my $people    = $person_rs->list_people( $role, $opts );

         $fields->{assignee} = bind 'assignee', [ [ NUL, NUL ], @{ $people } ];
      }

      $slot_type eq 'rider' and $fields->{request_bike}
            = bind( 'request_bike', TRUE, { container_class => 'right-last' } );
   }

   $fields->{confirm  } = $_confirm_slot_button->( $req, $action );
   $fields->{slot_href} = uri_for_action( $req, $self->moniker.'/slot', $args );

   return $stash;
}

sub week_rota : Role(any) {
   my ($self, $req) = @_;

   my $today      =  time2str '%Y-%m-%d';
   my $rota_name  =  $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date  =  $req->uri_params->( 1, { optional => TRUE } ) // $today;
   my $rota_dt    =  to_dt $rota_date;
   my $page       =  {
      fields      => { nav => {
         lshift   => $self->$_left_shift( $req, $rota_name, $rota_dt ),
         next     => $self->$_next_week( $req, $rota_name, $rota_dt ),
         prev     => $self->$_prev_week( $req, $rota_name, $rota_dt ),
         rshift   => $self->$_right_shift( $req, $rota_name, $rota_dt ), }, },
      rota        => { headers => $_week_rota_headers->( $req, $rota_dt ),
                       name    => $rota_name,
                       rows    => [] },
      template    => [ 'contents', 'rota', 'week-table' ],
      title       => $_week_rota_title->( $req, $rota_name, $rota_dt ), };
   my $opts       =  {
      after       => $rota_dt->clone->subtract( days => 1),
      before      => $rota_dt->clone->add( days => 7 ),
      rota_type   => $self->$_find_rota_type_id( $rota_name ) };
   my $event_rs   =  $self->schema->resultset( 'Event' );
   my $slot_rs    =  $self->schema->resultset( 'Slot' );
   my $tport_rs   =  $self->schema->resultset( 'Transport' );
   my $vehicle_rs =  $self->schema->resultset( 'Vehicle' );
   my $vreq_rs    =  $self->schema->resultset( 'VehicleRequest' );
   my @slots      =  $slot_rs->list_slots_for( $opts )->all;
   my @uv_events  =  $vreq_rs->search_for_events_with_unassigned_vreqs( $opts );
   my @tports     =  $tport_rs->search_for_assigned_vehicles( $opts )->all;
   my @v_events   =  $event_rs->search_for_vehicle_events( $opts )->all;
   my $rows       =  $page->{rota}->{rows};
   my $slot_cache =  [];

   $self->update_navigation_date( $req, $_local_dt->( $rota_dt ) );

   push @{ $rows }, $self->$_week_rota_requests
      ( $req, $page, $rota_dt, $slot_cache, \@slots, \@uv_events );

   for my $tuple (@{ $vehicle_rs->list_vehicles( { service => TRUE } ) }) {
      push @{ $rows }, $self->$_week_rota_assignments
         ( $req, $page, $rota_dt, $tuple, $slot_cache, \@tports, \@v_events );
   }

   return $self->get_stash( $req, $page );
}

sub yield_slot_action : Role(rota_manager) Role(bike_rider) Role(controller)
                        Role(driver) {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $slot_name = $params->( 2 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_by_shortcode( $req->username );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $slot_name, 3;

   $person->yield_slot( $rota_name, to_dt( $rota_date ), $shift_type,
                        $slot_type, $subslot );

   my $args     = [ $rota_name, $rota_date ];
   my $location = uri_for_action( $req, 'sched/day_rota', $args );
   my $label    = slot_identifier( $rota_name, $rota_date,
                                   $shift_type, $slot_type, $subslot );
   my $message  = [ 'User [_1] yielded slot [_2]', $person->label, $label ];

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Schedule - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Schedule;
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
