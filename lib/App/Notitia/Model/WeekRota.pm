package App::Notitia::Model::WeekRota;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_cell p_container p_hidden
                                p_row p_select p_span p_table );
use App::Notitia::Util      qw( js_server_config js_submit_config
                                locm make_tip register_action_paths
                                slot_limit_index to_dt uri_for_action );
use Class::Null;
use Class::Usul::Time       qw( time2str );
use Scalar::Util            qw( blessed );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'week';

register_action_paths
   'week/alloc_key' => 'allocation-key',
   'week/alloc_table' => 'allocation-table',
   'week/allocation' => 'vehicle-allocation',
   'week/week_rota' => 'week-rota';

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

# Private functions
my $_local_dt = sub {
   return $_[ 0 ]->clone->set_time_zone( 'local' );
};

my $_add_event_tip = sub {
   my ($req, $page, $event) = @_;

   my $href = uri_for_action $req, 'event/event_info', [ $event->uri ];

   push @{ $page->{literal_js} }, js_server_config
      $event->uri, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_add_slot_tip = sub {
   my ($req, $page, $id) = @_;

   my $name    = $page->{rota}->{name};
   my $actionp = 'month/assign_summary';
   my $href    = uri_for_action $req, $actionp, [ "${name}_${id}" ];

   push @{ $page->{literal_js} }, js_server_config
      $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_add_v_event_tip = sub {
   my ($req, $page, $event) = @_;

   my $href = uri_for_action $req, 'event/vehicle_info', [ $event->uri ];

   push @{ $page->{literal_js} }, js_server_config
      $event->uri, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_add_vreq_tip = sub {
   my ($req, $page, $event) = @_;

   my $actionp = 'asset/request_info';
   my $href    = uri_for_action $req, $actionp, [ $event->uri ];
   my $id      = 'request-'.$event->uri;

   push @{ $page->{literal_js} }, js_server_config
      $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_add_journal = sub {
   my ($journal, $vrn, $start, $keeper) = @_;

   my $list = $journal->{ $vrn } //= []; my $i = 0;

   while (my $entry = $list->[ $i ]) { $entry->{start} < $start and last; $i++ }

   splice @{ $list }, $i, 0, { keeper => $keeper, start => $start };

   return;
};

my $_alloc_cell_headers = sub {
   my $req = shift; my @headings = qw( Shift Vehicle R Name C4 );

   return [ map { { value => $_ } } @headings  ];
};

my $_onclick_relocate = sub {
   my ($page, $k, $href) = @_;

   push @{ $page->{literal_js} },
      js_submit_config $k, 'click', 'location', [ "${href}" ];

   return;
};

my $_operators_vehicle = sub {
   my ($slot, $cache) = @_; my $id = $slot->operator->id or return NUL;

   exists $cache->{ $id } and return $cache->{ $id }; my $label;

   for my $pv ($slot->operator_vehicles->all) {
      $label = $pv->type eq '4x4' ? '4' : $pv->type eq 'car' ? 'C' : FALSE;

      $label and last;
   }

   return $cache->{ $id } = $label || 'N';
};

my $_week_label = sub {
   my ($req, $date, $cno) = @_;

   my $local_dt = $_local_dt->( $date )->add( days => $cno );
   my $key = 'week_rota_heading_'.(lc $local_dt->day_abbr);
   my $v = locm $req, $key, $local_dt->day;

   return { class => 'day-of-week', value => $v };
};

my $_week_rota_headers = sub {
   my ($req, $date) = @_;

   return [ { class => '', value => 'vehicle', },
            map {  $_week_label->( $req, $date, $_ ) } 0 .. 6 ];
};

my $_week_rota_title = sub {
   my ($req, $rota_name, $date) = @_; my $local_dt = $_local_dt->( $date );

   $date = $local_dt->day.SPC.$local_dt->month_name.SPC.$local_dt->year;

   return locm $req, 'week_rota_title', locm( $req, $rota_name ), $date;
};

my $_find_keeper = sub {
   my ($list, $start) = @_; my $i = 0;

   while (my $entry = $list->[ $i ]) { $entry->{start} < $start and last; $i++ }

   return $list->[ $i ] ? $list->[ $i ]->{keeper} : FALSE;
};

my $_calculate_distance = sub {
   my ($keeper, $assignee) = @_;

   ($keeper and $keeper->coordinates and $assignee and $assignee->coordinates)
      or return;

   my ($kx, $ky) = split m{ , }mx, $keeper->coordinates;
   my ($ax, $ay) = split m{ , }mx, $assignee->coordinates;

   return int( 0.5 + sqrt( ($kx - $ax)**2 + ($ky - $ay)**2 ) / 1000 );
};

my $_vehicle_label = sub {
   my ($data, $vehicle) = @_; my $vrn = $vehicle->vrn;

   my $keeper = $_find_keeper->( $data->{journal}->{ $vrn }, $data->{start} );
   my $distance = $_calculate_distance->( $keeper, $data->{assignee} );

   return $distance ? $vehicle->name." (${distance})" : $vehicle->name;
};

my $_vehicle_list = sub {
   my ($data, $vrn) = @_; $vrn //= NUL;

   return [ [ NUL, NUL ], map { [ $_vehicle_label->( $data, $_ ), $_->vrn, {
      selected => $vrn eq $_->vrn ? TRUE : FALSE } ] } @{ $data->{vehicles} } ];
};

my $_vehicle_select_cell = sub {
   my ($page, $data, $form_name, $href, $action, $vrn) = @_;

   my $disabled = $form_name eq 'disabled' ? TRUE : FALSE;
   my $form = blank_form $form_name, $href, {
      class => 'spreadsheet-fixed-form align-center' };
   my $jsid = "vehicle-${form_name}";

   push @{ $page->{literal_js} //= [] }, js_submit_config
      $jsid, 'change', 'submitForm', [ $action, $form_name ];
   p_select $form, 'vehicle', $_vehicle_list->( $data, $vrn ), {
      class => "spreadsheet-select submit", disabled => $disabled,
      id => $jsid, label => NUL };
   p_hidden $form, 'vehicle_original', $vrn;

   return { class => 'spreadsheet-fixed-select', value => $form };
};

my $_alloc_cell_slot_row = sub {
   my ($req, $page, $cache, $data, $dt, $slot_key) = @_;

   my $local_ymd = $_local_dt->( $dt )->ymd;
   my $dt_key = "${local_ymd}_${slot_key}";
   my $slot = $data->{slots}->{ $dt_key }; $slot or $slot = Class::Null->new;
   my $style = NUL; $slot->vehicle and $slot->vehicle->colour
      and $style = 'background-color: '.$slot->vehicle->colour.';';
   my $operator = $slot->operator;
   my $row = [];

   p_cell $row, { class => 'rota-header align-center',
                  value => locm $req, "${slot_key}_abbrv" };

   if ($operator->id and $slot->bike_requested) {
      my $args = [ $page->{rota_name}, $local_ymd, $slot_key ];
      my $href = uri_for_action $req, 'asset/vehicle', $args;
      my $vrn  = $slot->vehicle ? $slot->vehicle->vrn : NUL;
      my $opts = { assignee => $operator,
                   journal => $data->{journal},
                   start => ($slot->duration)[ 0 ],
                   vehicles => $data->{vehicles}->{bike} };

      p_cell $row, $_vehicle_select_cell->
         ( $page, $opts, $dt_key, $href, 'assign_vehicle', $vrn );
   }
   else { p_cell $row, { class => 'spreadsheet-fixed-select', value => NUL } }

   p_cell $row, { class => 'narrow align-center',
                  value => $operator->id ? $operator->region : NUL };
   p_cell $row, { class => 'spreadsheet-fixed-cell', style => $style,
                  value => $operator->id ? $operator->label : 'Vacant' };
   p_cell $row, { class => 'narrow align-center',
                  value => $_operators_vehicle->( $slot, $cache ) };
   return $row;
};

my $_alloc_key_row = sub {
   my ($req, $assets, $now, $vehicle) = @_;

   my $keeper = $assets->find_last_keeper( $req, $now, $vehicle );
   my $details = $vehicle->name.', '.$vehicle->notes.', '.$vehicle->vrn;
   my $style = NUL; $vehicle->colour
      and $style = 'background-color: '.$vehicle->colour.';';
   my $row = [];

   p_cell $row, { value => ucfirst $details };
   p_cell $row, { value => locm $req, $vehicle->type };
   p_cell $row, { class => 'narrow align-center',
                  value => $keeper ? $keeper->region : NUL };
   p_cell $row, { style => $style,
                  value => $keeper ? $keeper->label : NUL };

   my $location = $keeper ? $keeper->location : NUL;

   $location and $location .= ' ('.$keeper->outer_postcode.')';

   p_cell $row, { value => $location };

   return $row;
};

my $_alloc_key_headers = sub {
   my $req = shift;

   my @headings = ( 'Vehicle Details', 'Type', 'R',
                    'Current Keeper', 'Keeper Location' );

   return [ map { { class => 'rota-header', value => locm $req, $_ } }
            @headings  ];
};

my $_alloc_table_label = sub {
   my ($req, $date, $cno) = @_;

   my $local_dt = $_local_dt->( $date )->add( days => $cno );
   my $key = 'alloc_table_heading_'.(lc $local_dt->day_abbr);
   my $v = locm $req, $key, $local_dt->day, $local_dt->month_name;

   return { class => 'day-of-week', value => $v };
};

my $_alloc_table_headers = sub {
   my ($req, $date) = @_;

   return [ map { $_alloc_table_label->( $req, $date, $_ ) } 0 .. 6 ];
};

my $_alloc_cell_add_owner = sub {
   my ($row, $event, $style) = @_;

   p_cell $row, { class => 'align-center', value => $event->owner->region };
   p_cell $row, { class => 'spreadsheet-fixed-cell',
                  style => $style, value => $event->owner->label };
   p_cell $row, { value => NUL };
   return;
};

my $_alloc_cell_event_row = sub {
   my ($req, $page, $data, $count, $tuple) = @_;

   my $event = $tuple->[ 0 ]; my $style = NUL;

   my $href = uri_for_action $req, 'asset/vehicle', [ $event->uri ];

   my $row = []; my $cell = p_cell $row, { class => 'align-center' };

   my $id = $event->uri; blessed $tuple->[ 1 ] or $id = "request-${id}";

   p_span $cell, '&dagger;', {
      class => 'table-cell-help server tips', id => $id,
      title => locm $req, 'Event Information' };

   my $action = 'assign_vehicle';
   my $opts = { assignee => $event->owner, journal => $data->{journal},
                start => ($event->duration)[ 0 ] };

   if (blessed $tuple->[ 1 ]) {
      my $vehicle = $tuple->[ 1 ];

      my $vrn = $vehicle->vrn; my $form_name = $event->uri."-${vrn}";

      $opts->{vehicles} = $data->{vehicles}->{ $vehicle->type };

      p_cell $row, $_vehicle_select_cell->
         ( $page, $opts, $form_name, $href, $action, $vrn );
      $_add_event_tip->( $req, $page, $event );
      $vehicle->colour and $style = 'background-color: '.$vehicle->colour.';';
   }
   else {
      my $type = $tuple->[ 1 ];
      my $form_name = $event->uri."-${type}-${count}";

      $opts->{vehicles} = $data->{vehicles}->{ $type };

      p_cell $row, $_vehicle_select_cell->
         ( $page, $opts, $form_name, $href, $action );
      $_add_vreq_tip->( $req, $page, $event );
   }

   $_alloc_cell_add_owner->( $row, $event, $style );

   return $row;
};

my $_alloc_cell_vevent_row = sub {
   my ($req, $page, $data, $vevent) = @_; my $style = NUL;

   my $vehicle = $vevent->vehicle; $vehicle->colour
      and $style = 'background-color: '.$vehicle->colour.';';

   my $row = []; my $cell = p_cell $row, { class => 'align-center' };

   p_span $cell, '&dagger;', {
      class => 'table-cell-help server tips', id => $vevent->uri,
      title => locm $req, 'Vehicle Event Information' };

   my $opts = { assignee => $vevent->owner, journal => $data->{journal},
                start => ($vevent->duration)[ 0 ], vehicles => [ $vehicle ] };

   p_cell $row, $_vehicle_select_cell->
      ( $page, $opts, 'disabled', NUL, NUL, $vehicle->vrn );

   $_alloc_cell_add_owner->( $row, $vevent, $style );
   $_add_v_event_tip->( $req, $page, $vevent );
   return $row;
};

my $_alloc_cell = sub {
   my ($req, $page, $v_cache, $data, $cno) = @_;

   my $name = $page->{name};
   my $rota_dt = $page->{rota_dt};
   my $limits = $page->{limits};
   my $dr_max = $limits->[ slot_limit_index 'day', 'rider' ];
   my $nr_max = $limits->[ slot_limit_index 'night', 'rider' ];
   my $table = blank_form {
      class => 'embeded-spreadsheet-table', type => 'table' };
   my $dt = $rota_dt->clone->add( days => $cno );
   my $count = 0;

   $table->{headers} = $_alloc_cell_headers->( $req );

   for my $key (map { "day_rider_${_}" } 0 .. $dr_max - 1) {
      p_row $table, $_alloc_cell_slot_row->
         ( $req, $page, $v_cache, $data, $dt, $key );
   }

   for my $key (map { "night_rider_${_}" } 0 .. $nr_max - 1) {
      p_row $table, $_alloc_cell_slot_row->
         ( $req, $page, $v_cache, $data, $dt, $key );
   }

   for my $tuple (@{ $data->{events}->{ $_local_dt->( $dt )->ymd } // [] }) {
      p_row $table, $_alloc_cell_event_row->
         ( $req, $page, $data, $count++, $tuple );
   }

   for my $vevent (@{ $data->{vevents}->{ $_local_dt->( $dt )->ymd } // [] }) {
      p_row $table, $_alloc_cell_vevent_row->( $req, $page, $data, $vevent );
   }

   return { class => 'embeded', value => $table };
};

my $_allocation_js = sub {
   my ($req, $moniker, $rota_name, $rota_dt) = @_;

   my $args = [ $rota_name, $_local_dt->( $rota_dt )->ymd ];
   my $href1 = uri_for_action $req, "${moniker}/alloc_table", $args;

   $args = [ $rota_name, $_local_dt->( $rota_dt )->add( days => 7 )->ymd ];

   my $href2 = uri_for_action $req, "${moniker}/alloc_table", $args;
   my $href3 = uri_for_action $req, "${moniker}/alloc_key";

   return [ js_server_config( 'allocation-wk1', 'load',
                              'request', [ "${href1}", 'allocation-wk1' ] ),
            js_server_config( 'allocation-wk2', 'load',
                              'request', [ "${href2}", 'allocation-wk2' ] ),
            js_server_config( 'allocation-key', 'load',
                              'request', [ "${href3}", 'allocation-key' ] ) ];
};

my $_week_rota_assignments = sub {
   my ($req, $page, $rota_dt, $cache, $tports, $events, $tuple) = @_;

   my $rota_name = $page->{rota}->{name};
   my $class = 'narrow week-rota submit server tips';
   my $vehicle = $tuple->[ 1 ];
   my $style = NUL; $vehicle->colour
      and $style = 'background-color: '.$vehicle->colour.';';
   my $row = [ { class => 'narrow', style => $style, value => $tuple->[ 0 ] } ];

   for my $cno (0 .. 6) {
      my $date  = $rota_dt->clone->add( days => $cno );
      my $table = { class => 'week-rota', rows => [], type => 'table' };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => locm( $req, 'Rider Assignment' ),
                    value => locm( $req, $_->[ 1 ]->key ) } ] }
         map  { my $href = uri_for_action $req, 'day/day_rota',
                           [ $rota_name, $_local_dt->( $date )->ymd ];
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { my $id = $_local_dt->( $date )->ymd.'_'.$_->key;
                $_add_slot_tip->( $req, $page, $id ); [ $id, $_ ] }
         grep { $_->vehicle->vrn eq $vehicle->vrn }
         grep { $_->bike_requested and $_->vehicle }
             @{ $cache->[ $cno ] };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => locm( $req, 'Event Information' ),
                    value => $_->[ 1 ]->event->name } ] }
         map  { my $href = uri_for_action $req, 'asset/request_vehicle',
                           [ $_->[ 0 ] ];
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { $_add_event_tip->( $req, $page, $_->event );
                [ $_->event->uri, $_ ] }
         grep { $_->vehicle->vrn eq $vehicle->vrn }
         grep { $_->event->start_date eq $date } @{ $tports };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => locm( $req, 'Vechicle Event' ),
                    value => $_->[ 1 ]->name } ] }
         map  { my $href = uri_for_action $req, 'event/vehicle_event',
                           [ $_->[ 1 ]->vehicle->vrn, $_->[ 0 ] ];
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { $_add_v_event_tip->( $req, $page, $_ ); [ $_->uri, $_ ] }
         grep { $_->vehicle->vrn eq $vehicle->vrn }
         grep { $_->start_date eq $date } @{ $events };

      push @{ $row }, { class => 'narrow embeded', value => $table };
   }

   return $row;
};

# Private methods
my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

my $_initialise_journal = sub {
   my ($self, $req, $rota_dt, $vehicles) = @_;

   my $asset = $self->components->{asset}; my $journal = {};

   for my $type (keys %{ $vehicles }) {
      for my $vehicle (@{ $vehicles->{ $type } }) {
         my $keeper = $asset->find_last_keeper( $req, $rota_dt, $vehicle );

         $_add_journal->( $journal, $vehicle->vrn, $rota_dt, $keeper );
      }
   }

   return $journal;
};

my $_left_shift = sub {
   my ($self, $req, $rota_name, $date) = @_;

   my $actionp = $self->moniker.'/week_rota';

   $date = $_local_dt->( $date )->truncate( to => 'day' )
                                ->subtract( days => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_next_week_uri = sub {
   my ($self, $req, $method, $rota_name, $date) = @_;

   my $actionp = $self->moniker."/${method}";

   $date = $_local_dt->( $date )->truncate( to => 'day' )->add( weeks => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_next_week = sub {
   my ($self, $req, $method, $rota_name, $date) = @_;

   my $href = $self->$_next_week_uri( $req, $method, $rota_name, $date );

   return f_link 'next-week', $href, {
      class => 'next-rota', request => $req, value => locm $req, 'Next' };
};

my $_prev_week_uri = sub {
   my ($self, $req, $method, $rota_name, $date) = @_;

   my $actionp = $self->moniker."/${method}";

   $date = $_local_dt->( $date )->truncate( to => 'day' )
                                ->subtract( weeks => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_prev_week = sub {
   my ($self, $req, $method, $rota_name, $date) = @_;

   my $href = $self->$_prev_week_uri( $req, $method, $rota_name, $date );

   return f_link 'prev-week', $href, {
      class => 'prev-rota', request => $req, value => locm $req, 'Prev' };
};

my $_right_shift = sub {
   my ($self, $req, $rota_name, $date) = @_;

   my $actionp = $self->moniker.'/week_rota';

   $date = $_local_dt->( $date )->truncate( to => 'day' )->add( days => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_search_for_vehicle_events = sub {
   my ($self, $opts, $journal) = @_; my $vevents = {};

   $opts = { %{ $opts // {} } }; $journal //= {};

   my $event_rs = $self->schema->resultset( 'Event' );

   $opts->{prefetch} //= [ 'end_rota', 'owner', 'start_rota', 'vehicle' ];

   for my $vevent ($event_rs->search_for_vehicle_events( $opts )->all) {
      my $k = $_local_dt->( $vevent->start_date )->ymd;

      push @{ $vevents->{ $k } //= [] }, $vevent;

      my $start = ($vevent->duration)[ 0 ]; my $vehicle = $vevent->vehicle;

      $_add_journal->( $journal, $vehicle->vrn, $start, $vevent->owner );
   }

   return $vevents;
};

my $_search_for_vehicles = sub {
   my $self = shift; my $vehicles = {};

   my $rs = $self->schema->resultset( 'Vehicle' );

   for my $vehicle ($rs->search_for_vehicles( { service => TRUE } )->all) {
      push @{ $vehicles->{ $vehicle->type } //= [] }, $vehicle;
   }

   return $vehicles;
};

my $_search_for_events = sub {
   my ($self, $opts, $journal) = @_; my $events = {};

   $opts = { %{ $opts // {} } }; $journal //= {};

   my $vreq_rs = $self->schema->resultset( 'VehicleRequest' );

   for my $tuple ($vreq_rs->search_for_unassigned_vreqs( $opts )) {
      my $vreq = $tuple->[ 0 ];
      my $k = $_local_dt->( $vreq->event->start_date )->ymd;

      for my $count (0 .. $tuple->[ 1 ] - 1) {
         push @{ $events->{ $k } //= [] }, [ $vreq->event, $vreq->type->name ];
      }
   }

   my $tport_rs = $self->schema->resultset( 'Transport' );

   $opts->{prefetch} = [ { 'event' => [ 'owner', 'start_rota' ] }, 'vehicle' ];

   for my $tport ($tport_rs->search_for_assigned_vehicles( $opts )->all) {
      my $k = $_local_dt->( $tport->event->start_date )->ymd;
      my $vehicle = $tport->vehicle;

      push @{ $events->{ $k } //= [] }, [ $tport->event, $vehicle ];

      my $start = ($tport->event->duration)[ 0 ];

      $_add_journal->( $journal, $vehicle->vrn, $start, $tport->event->owner );
   }

   return $events;
};

my $_search_for_slots = sub {
   my ($self, $opts, $journal) = @_;

   $opts = { %{ $opts // {} } }; $journal //= {};

   my $slot_rs = $self->schema->resultset( 'Slot' ); my $slots = {};

   for my $slot (grep { $_->type_name->is_rider }
                 $slot_rs->search_for_slots( $opts )->all) {
      my $k = $_local_dt->( $slot->start_date )->ymd.'_'.$slot->key;

      $slots->{ $k } = $slot; $slot->vehicle or next;

      my $start = ($slot->duration)[ 0 ];

      $_add_journal->( $journal, $slot->vehicle->vrn, $start, $slot->operator );
   }

   return $slots;
};

my $_week_rota_requests = sub {
   my ($self, $req, $page, $rota_dt, $slot_cache, $opts) = @_;

   my $slot_rs = $self->schema->resultset( 'Slot' );
   my $slots = [ $slot_rs->search_for_slots( $opts )->all ];
   my $vreq_rs = $self->schema->resultset( 'VehicleRequest' );
   my $events = [ $vreq_rs->search_for_events_with_unassigned_vreqs( $opts ) ];
   my $rota_name = $page->{rota}->{name};
   my $class = 'narrow week-rota submit server tips';
   my $row = [ { class => 'narrow', value => 'Requests' } ];

   for my $cno (0 .. 6) {
      my $date  = $rota_dt->clone->add( days => $cno );
      my $table = { class => 'week-rota', rows => [], type => 'table' };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => locm( $req, 'Rider Assignment' ),
                    value => locm( $req, $_->[ 1 ]->key ) } ] }
         map  { my $href = uri_for_action $req, 'day/day_rota',
                           [ $rota_name, $_local_dt->( $date )->ymd ];
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { my $id = $_local_dt->( $date )->ymd.'_'.$_->key;
                $_add_slot_tip->( $req, $page, $id ); [ $id, $_ ] }
         grep { $_->bike_requested and not $_->vehicle }
         map  { push @{ $slot_cache->[ $cno ] }, $_; $_ }
         grep { $_->date eq $date } @{ $slots };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => 'request-'.$_->[ 0 ],
                    title => locm( $req, 'Vehicle Request' ),
                    value => $_->[ 1 ]->name } ] }
         map  { my $href = uri_for_action $req, 'asset/request_vehicle',
                           [ $_->[ 0 ] ];
                $_onclick_relocate->( $page, 'request-'.$_->[ 0 ], $href ); $_ }
         map  { $_add_vreq_tip->( $req, $page, $_ ); [ $_->uri, $_ ] }
         grep { $_->start_date eq $date } @{ $events };

      push @{ $row }, { class => 'narrow embeded', value => $table };
   }

   return $row;
};

# Public methods
sub alloc_key : Role(rota_manager) {
   my ($self, $req) = @_;

   my $stash = $self->dialog_stash( $req );
   my $table = $stash->{page}->{forms}->[ 0 ] = blank_form {
      class => 'key-table', type => 'table' };
   my $columns = [ qw( colour id name notes vrn ) ];
   my $vehicles = $self->schema->resultset( 'Vehicle' )->search_for_vehicles( {
      columns => $columns, service => TRUE } );
   my $assets = $self->components->{asset};
   my $now = to_dt time2str;

   $table->{headers} = $_alloc_key_headers->( $req );

   p_row $table, [ map { $_alloc_key_row->( $req, $assets, $now, $_ ) }
                   $vehicles->all ];

   return $stash;
}

sub alloc_table : Role(rota_manager) {
   my ($self, $req) = @_;

   my $today = time2str '%Y-%m-%d';
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $req->uri_params->( 1, { optional => TRUE } ) // $today;
   my $rota_dt = to_dt $rota_date;
   my $stash = $self->dialog_stash( $req );
   my $table = $stash->{page}->{forms}->[ 0 ]
             = blank_form { class => 'spreadsheet-table', type => 'table' };
   my $opts = {
      after => $rota_dt->clone->subtract( days => 1),
      before => $rota_dt->clone->add( days => 7 ),
      rota_type => $self->$_find_rota_type( $rota_name )->id };
   my $vehicles = $self->$_search_for_vehicles();
   my $journal = $self->$_initialise_journal( $req, $rota_dt, $vehicles );
   my $events = $self->$_search_for_events( $opts, $journal );
   my $slots = $self->$_search_for_slots( $opts, $journal );
   my $vevents = $self->$_search_for_vehicle_events( $opts, $journal );
   my $data = { vehicles => $vehicles, events => $events, journal => $journal,
                slots => $slots, vevents => $vevents };
   my $page = $stash->{page};
   my $row = p_row $table;
   my $v_cache = {};

   $table->{headers} = $_alloc_table_headers->( $req, $rota_dt );
   $page->{limits} = $self->config->slot_limits;
   $page->{moniker} = $self->moniker;
   $page->{rota_name} = $rota_name;
   $page->{rota_dt} = $rota_dt;

   p_cell $row, [ map { $_alloc_cell->( $req, $page, $v_cache, $data, $_ ) }
                  0 .. 6 ];

   push @{ $page->{literal_js} }, 'behaviour.rebuild();';

   return $stash;
}

sub allocation : Role(rota_manager) {
   my ($self, $req) = @_;

   my $today = time2str '%Y-%m-%d';
   my $moniker = $self->moniker;
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $req->uri_params->( 1, { optional => TRUE } ) // $today;
   my $rota_dt = to_dt $rota_date;
   my $list = blank_form { class => 'spreadsheet' };
   my $form = blank_form {
      class => 'spreadsheet-key-table server', id => 'allocation-key' };
   my $page = {
      fields => { nav => {
         next => $self->$_next_week( $req, 'allocation', $rota_name, $rota_dt ),
         prev => $self->$_prev_week( $req, 'allocation', $rota_name, $rota_dt )
         }, },
      forms => [ $list, $form ],
      literal_js => $_allocation_js->( $req, $moniker, $rota_name, $rota_dt ),
      off_grid => TRUE,
      template => [ 'none', 'custom/two-week-table' ],
      title => locm $req, 'Vehicle Allocation'
   };

   p_container $list, NUL, { class => 'server', id => 'allocation-wk1' };
   p_container $list, NUL, { class => 'server', id => 'allocation-wk2' };

   return $self->get_stash( $req, $page );
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
         next     => $self->$_next_week_uri
            ( $req, 'week_rota', $rota_name, $rota_dt ),
         prev     => $self->$_prev_week_uri
            ( $req, 'week_rota', $rota_name, $rota_dt ),
         rshift   => $self->$_right_shift( $req, $rota_name, $rota_dt ), }, },
      rota        => { headers => $_week_rota_headers->( $req, $rota_dt ),
                       name    => $rota_name,
                       rows    => [] },
      template    => [ '/menu', 'custom/week-table' ],
      title       => $_week_rota_title->( $req, $rota_name, $rota_dt ), };
   my $opts       =  {
      after       => $rota_dt->clone->subtract( days => 1),
      before      => $rota_dt->clone->add( days => 7 ),
      rota_type   => $self->$_find_rota_type( $rota_name )->id };
   my $event_rs   =  $self->schema->resultset( 'Event' );
   my $events     =  [ $event_rs->search_for_vehicle_events( $opts )->all ];
   my $tport_rs   =  $self->schema->resultset( 'Transport' );
   my $tports     =  [ $tport_rs->search_for_assigned_vehicles( $opts )->all ];
   my $vehicle_rs =  $self->schema->resultset( 'Vehicle' );
   my $rows       =  $page->{rota}->{rows};
   my $slot_cache =  [];

   $self->update_navigation_date( $req, $_local_dt->( $rota_dt ) );

   push @{ $rows }, $self->$_week_rota_requests
      ( $req, $page, $rota_dt, $slot_cache, $opts );

   for my $tuple (@{ $vehicle_rs->list_vehicles( { service => TRUE } ) }) {
      push @{ $rows }, $_week_rota_assignments->
         ( $req, $page, $rota_dt, $slot_cache, $tports, $events, $tuple );
   }

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::WeekRota - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::WeekRota;
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
