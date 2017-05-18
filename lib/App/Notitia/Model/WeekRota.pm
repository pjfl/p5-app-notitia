package App::Notitia::Model::WeekRota;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SPC TRUE );
use App::Notitia::DOM       qw( new_container p_cell p_container p_hidden
                                p_js p_link p_row p_select p_span p_table );
use App::Notitia::Util      qw( contrast_colour js_server_config js_submit_config local_dt
                                locm make_tip register_action_paths
                                slot_limit_index to_dt );
use Class::Null;
use Class::Usul::Time       qw( time2str );
use Scalar::Util            qw( blessed );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

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
my $_add_event_tip = sub {
   my ($req, $page, $event) = @_;

   my $href = $req->uri_for_action( 'event/event_info', [ $event->uri ] );

   p_js $page, js_server_config
      $event->uri, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_add_slot_tip = sub {
   my ($req, $page, $id) = @_;

   my $name    = $page->{rota}->{name};
   my $actionp = 'month/assign_summary';
   my $href    = $req->uri_for_action( $actionp, [ "${name}_${id}" ] );

   p_js $page, js_server_config
      $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_add_v_event_tip = sub {
   my ($req, $page, $event) = @_;

   my $href = $req->uri_for_action( 'event/vehicle_info', [ $event->uri ] );

   p_js $page, js_server_config
      $event->uri, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_add_vreq_tip = sub {
   my ($req, $page, $event) = @_;

   my $actionp = 'asset/request_info';
   my $href    = $req->uri_for_action( $actionp, [ $event->uri ] );
   my $id      = 'request-'.$event->uri;

   p_js $page, js_server_config
      $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_add_journal = sub {
   my ($journal, $vrn, $start, $tuple) = @_;

   my $list = $journal->{ $vrn } //= []; my $i = 0;

   while (my $entry = $list->[ $i ]) { $entry->{start} < $start and last; $i++ }

   my $location = $tuple->[ 1 ] && $tuple->[ 1 ]->coordinates ? $tuple->[ 1 ]
                : $tuple->[ 0 ];

   splice @{ $list }, $i, 0, { location => $location, start => $start };

   return;
};

my $_alloc_cell_headers = sub {
   my ($req, $cno) = @_; my @headings = qw( Vehicle R Name C4 );

   my $headers = [ map { { value => $_ } } @headings  ];

   $cno == 0 and unshift @{ $headers }, { value => 'Shift' };

   return $headers;
};

my $_alloc_query_params = sub {
   my $req  = shift;  my $sess = $req->session;

   my $cols = $sess->display_cols; my $rows = $sess->display_rows;

   $cols = $req->query_params->( 'cols', { optional => TRUE } ) // $cols;
   $rows = $req->query_params->( 'rows', { optional => TRUE } ) // $rows;

   $sess->display_cols( $cols ); $sess->display_rows( $rows );

   return { cols => $cols, rows => $rows };
};

my $_onchange_submit = sub {
   my ($page, $k, $form_id) = @_; $form_id //= 'display_control';

   (my $form_name = $form_id) =~ s{ _ }{-}gmx;

   p_js $page, js_submit_config $k, 'change', 'submitForm',
                  [ $form_id, $form_name ];

   return;
};

my $_onclick_relocate = sub {
   my ($page, $k, $href) = @_;

   p_js $page, js_submit_config $k, 'click', 'location', [ "${href}" ];

   return;
};

my $_operators_vehicle = sub {
   my $slot = shift; $slot->operator->id or return NUL;

   my $slov = $slot->operator_vehicle;

   return $slov && $slov->type eq '4x4' ? '4'
        : $slov && $slov->type eq 'car' ? 'C'
        : NUL;
};

my $_select_number = sub {
   my ($max, $selected) = @_;

   return [ map { [ $_ , $_, { selected => $selected eq $_? TRUE : FALSE } ] }
            1 .. $max ];
};

my $_week_label = sub {
   my ($req, $date, $cno) = @_;

   my $local_dt = local_dt( $date )->add( days => $cno );
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
   my ($req, $rota_name, $date) = @_; my $local_dt = local_dt $date;

   $date = $local_dt->day.SPC.$local_dt->month_name.SPC.$local_dt->year;

   return locm $req, 'week_rota_title', locm( $req, $rota_name ), $date;
};

my $_find_location = sub {
   my ($list, $start) = @_; my $i = 0;

   while (my $entry = $list->[ $i ]) { $entry->{start} < $start and last; $i++ }

   return $list->[ $i ] ? $list->[ $i ]->{location} : FALSE;
};

my $_calculate_distance = sub { # In metres
   my ($location, $assignee) = @_;

   ($location and $location->coordinates and
    $assignee and $assignee->coordinates) or return;

   my ($lx, $ly) = split m{ , }mx, $location->coordinates;
   my ($ax, $ay) = split m{ , }mx, $assignee->coordinates;

   return int 0.5 + sqrt( ($lx - $ax)**2 + ($ly - $ay)**2 );
};

my $_crow2road = sub { # Distance on the road is always more than the crow flies
   my ($x, $factor) = @_;

   return ($x / $factor) + sqrt( ($x**2) - ($x / $factor)**2 );
};

my $_vehicle_label = sub {
   my ($data, $vehicle) = @_;

   my $list = $data->{journal}->{ $vehicle->vrn };
   my $location = $_find_location->( $list, $data->{start} );
   my $distance = $_calculate_distance->( $location, $data->{assignee} );

   $distance and $distance = $_crow2road->( $distance, 5 );
   $distance and $distance = int 0.5 + 5 * $distance / 8000; # Metres to miles

   return $distance ? $vehicle->name." (${distance} mls)" : $vehicle->name;
};

my $_vehicle_list = sub {
   my ($data, $vrn) = @_; $vrn //= NUL;

   return [ [ NUL, NUL ], map { [ $_vehicle_label->( $data, $_ ), $_->vrn, {
      selected => $vrn eq $_->vrn ? TRUE : FALSE } ] } @{ $data->{vehicles} } ];
};

my $_union = sub {
   return [ @{ $_[ 0 ]->{ $_[ 1 ]->[ 0 ] } // [] },
            @{ $_[ 0 ]->{ $_[ 1 ]->[ 1 ] } // [] } ];
};

my $_alloc_key_row = sub {
   my ($req, $assets, $keeper_dt, $vehicle) = @_;

   my $keeper = $assets->find_last_keeper( $req, $keeper_dt, $vehicle );
   my $details = $vehicle->name.', '.$vehicle->notes.', '.$vehicle->vrn;
   my $style = NUL; $vehicle->colour
      and $style = 'background-color: '.$vehicle->colour.';'.
                   'color: '.contrast_colour($vehicle->colour).';';
   my $row = [];

   p_cell $row, { value => ucfirst $details };
   p_cell $row, { value => locm $req, $vehicle->type };
   p_cell $row, { class => 'narrow align-center',
                  value => $keeper ? $keeper->[ 0 ]->region : NUL };
   p_cell $row, { style => $style,
                  value => $keeper ? $keeper->[ 0 ]->label : NUL };

   my $location = $keeper ? $keeper->[ 0 ]->location : NUL;

   $location and $location .= ' ('.$keeper->[ 0 ]->outer_postcode.')';

   p_cell $row, { value => $location };

   return $row;
};

my $_alloc_key_headers = sub {
   my ($req, $keeper_dt) = @_;

   my @headings = ( 'Vehicle Details', 'Type', 'R',
                    'Keeper at [_1] [_2] [_3]', 'Keeper Location' );

   return [ map { { class => 'rota-header', value => locm $req, $_,
                    $keeper_dt->day_abbr, $keeper_dt->day,
                    $keeper_dt->month_abbr } }
            @headings  ];
};

my $_alloc_table_label = sub {
   my ($req, $date, $cno) = @_;

   my $local_dt = local_dt( $date )->add( days => $cno );
   my $key = 'alloc_table_heading_'.(lc $local_dt->day_abbr);
   my $v = locm $req, $key, $local_dt->day, $local_dt->month_name;

   return { class => 'day-of-week', value => $v };
};

my $_alloc_table_headers = sub {
   my ($req, $date, $cols) = @_;

   return [ map { $_alloc_table_label->( $req, $date, $_ ) } 0 .. $cols - 1 ];
};

my $_alloc_cell_event_owner = sub {
   my ($req, $row, $event, $style, $id) = @_;

   p_cell $row, { class => 'align-center', value => $event->owner->region };

   my $cell = p_cell $row, {
      class => 'spreadsheet-fixed-cell', style => $style };

   my $text = $event->event_type eq 'person'
            ? 'Event Information' : 'Vehicle Event Information';

   p_span $cell, $event->owner->label, {
      class => 'table-cell-help server tips', id => $id,
      title => locm $req, $text };

   p_cell $row, { value => NUL };
   return;
};

my $_push_allocation_js = sub {
   my ($req, $page, $moniker, $dt) = @_; $dt = local_dt $dt;

   my $href = $req->uri_for_action( "${moniker}/alloc_key", [ $dt->ymd ] );

   p_js $page, js_server_config
      'allocation-key', 'load', 'request', [ "${href}", 'allocation-key' ];

   return;
};

my $_week_rota_assignments = sub {
   my ($req, $page, $rota_dt, $cache, $tports, $events, $tuple) = @_;

   my $rota_name = $page->{rota}->{name};
   my $class = 'narrow week-rota submit server tips';
   my $vehicle = $tuple->[ 1 ];
   my $style = NUL; $vehicle->colour
      and $style = 'background-color: '.$vehicle->colour.';'.
                   'color: '.contrast_colour($vehicle->colour).';';
   my $row = [ { class => 'narrow', style => $style, value => $tuple->[ 0 ] } ];

   for my $cno (0 .. 6) {
      my $date  = $rota_dt->clone->add( days => $cno );
      my $table = { class => 'week-rota', rows => [], type => 'table' };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => locm( $req, 'Rider Assignment' ),
                    value => locm( $req, $_->[ 1 ]->key ) } ] }
         map  { my $href = $req->uri_for_action
                   ( 'day/day_rota', [ $rota_name, local_dt( $date )->ymd ] );
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { my $id = local_dt( $date )->ymd.'_'.$_->key;
                $_add_slot_tip->( $req, $page, $id ); [ $id, $_ ] }
         grep { $_->vehicle->vrn eq $vehicle->vrn }
         grep { $_->vehicle_requested and $_->vehicle }
             @{ $cache->[ $cno ] };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => locm( $req, 'Event Information' ),
                    value => $_->[ 1 ]->event->name } ] }
         map  { my $href = $req->uri_for_action
                   ( 'asset/request_vehicle', [ $_->[ 0 ] ] );
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
         map  { my $href = $req->uri_for_action
                   ( 'event/vehicle_event', [ $_->[ 1 ]->vehicle->vrn,
                                              $_->[ 0 ] ] );
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { $_add_v_event_tip->( $req, $page, $_ ); [ $_->uri, $_ ] }
         grep { $_->vehicle->vrn eq $vehicle->vrn }
         grep { $_->start_date eq $date } @{ $events };

      push @{ $row }, { class => 'narrow embeded', value => $table };
   }

   return $row;
};

# Private methods
my $_vehicle_select_cell = sub {
   my ($self, $req, $page, $data, $form_name, $href, $action, $vrn) = @_;

   my $disabled = $form_name eq 'disabled' ? TRUE : FALSE;
   my $form = new_container $form_name, $href, {
      class => 'spreadsheet-fixed-form align-center' };
   my $jsid = "vehicle-${form_name}";

   $self->add_csrf_token( $req, $form );

   p_js $page, js_submit_config
      $jsid, 'change', 'submitForm', [ $action, $form_name ];
   p_select $form, 'vehicle', $_vehicle_list->( $data, $vrn ), {
      class => "spreadsheet-select submit", disabled => $disabled,
      id => $jsid, label => NUL };
   p_hidden $form, 'vehicle_original', $vrn;

   return { class => 'spreadsheet-fixed-select', value => $form };
};

my $_alloc_event_row = sub {
   my ($self, $req, $page, $data, $count, $tuple, $cno) = @_;

   my $event = $tuple->[ 0 ];
   my $href = $req->uri_for_action( 'asset/vehicle', [ $event->uri ] );
   my $opts = { assignee => $event->owner, journal => $data->{journal},
                start => ($event->duration)[ 0 ] };
   my $action = 'assign_vehicle';
   my $id = $event->uri;
   my $row = []; $cno == 0 and push @{ $row }, { value => NUL };
   my $style = NUL;

   if (blessed $tuple->[ 1 ]) {
      my $vehicle = $tuple->[ 1 ];
      my $vrn = $vehicle->vrn;
      my $form_name = $event->uri."-${vrn}";

      $opts->{vehicles} = $data->{vehicles}->{ $vehicle->type };

      p_cell $row, $self->$_vehicle_select_cell
         ( $req, $page, $opts, $form_name, $href, $action, $vrn );

      $_add_event_tip->( $req, $page, $event );
      $vehicle->colour and $style = 'background-color: '.$vehicle->colour.';'.
                                    'color: '.contrast_colour($vehicle->colour).';';
   }
   else {
      my $type = $tuple->[ 1 ];
      my $form_name = $event->uri."-${type}-${count}";

      $opts->{vehicles} = $data->{vehicles}->{ $type };

      p_cell $row, $self->$_vehicle_select_cell
         ( $req, $page, $opts, $form_name, $href, $action );

      $_add_vreq_tip->( $req, $page, $event );
      $id = "request-${id}";
   }

   $_alloc_cell_event_owner->( $req, $row, $event, $style, $id );

   return $row;
};

my $_alloc_slot_row = sub {
   my ($self, $req, $page, $data, $dt, $slot_key, $cno) = @_;

   my $local_ymd = local_dt( $dt )->ymd;
   my $dt_key = "${local_ymd}_${slot_key}";
   my $slot = $data->{slots}->{ $dt_key } // Class::Null->new;
   my $style = NUL; $slot->vehicle and $slot->vehicle->colour
      and $style = 'background-color: '.$slot->vehicle->colour.';'.
                   'color: '.contrast_colour($slot->vehicle->colour).';';
   my $operator = $slot->operator;
   my $row = [];

   $cno == 0 and p_cell $row, { class => 'rota-header align-center',
                                value => locm $req, "${slot_key}_abbrv" };

   if ($operator->id and $slot->vehicle_requested) {
      my $args = [ $page->{rota_name}, $local_ymd, $slot_key ];
      my $href = $req->uri_for_action( 'asset/vehicle', $args );
      my $vrn  = $slot->vehicle ? $slot->vehicle->vrn : NUL;
      my $vehicles = $slot->type_name->is_driver ?
                     $_union->( $data->{vehicles}, [ '4x4', 'car' ] )
                   : $slot->type_name->is_rider  ? $data->{vehicles}->{bike}
                   : [];
      my $opts = { assignee => $operator,
                   journal => $data->{journal},
                   start => ($slot->duration)[ 0 ],
                   vehicles => $vehicles };

      p_cell $row, $self->$_vehicle_select_cell
         ( $req, $page, $opts, $dt_key, $href, 'assign_vehicle', $vrn );
   }
   else { p_cell $row, { class => 'spreadsheet-fixed-select', value => NUL } }

   p_cell $row, { class => 'narrow align-center',
                  value => $operator->id ? $operator->region : NUL };
   p_cell $row, { class => 'spreadsheet-fixed-cell table-cell-label',
                  style => $style,
                  value => $operator->id ? $operator->label : 'Vacant' };
   p_cell $row, { class => 'narrow align-center',
                  value => $_operators_vehicle->( $slot ) };
   return $row;
};

my $_alloc_vevent_row = sub {
   my ($self, $req, $page, $data, $vevent, $cno) = @_;

   my $row = []; my $style = NUL;

   my $vehicle = $vevent->vehicle; $vehicle->colour
      and $style = 'background-color: '.$vehicle->colour.';'.
                   'color: '.contrast_colour($vehicle->colour).';';

   my $opts = { assignee => $vevent->owner, journal => $data->{journal},
                start => ($vevent->duration)[ 0 ], vehicles => [ $vehicle ] };

   p_cell $row, $self->$_vehicle_select_cell
      ( $req, $page, $opts, 'disabled', NUL, NUL, $vehicle->vrn );

   $_alloc_cell_event_owner->( $req, $row, $vevent, $style, $vevent->uri );
   $_add_v_event_tip->( $req, $page, $vevent );
   return $row;
};

my $_alloc_cell = sub {
   my ($self, $req, $page, $data, $cno) = @_;

   my $table = new_container {
      class => 'embeded-spreadsheet-table', type => 'table' };
   my $dt = $page->{rota_dt}->clone->add( days => $cno );
   my $limits = $page->{limits};
   my $count = 0;

   $table->{headers} = $_alloc_cell_headers->( $req, $cno );

   for my $pair ([ 'day',   'rider' ], [ 'day',   'driver' ],
                 [ 'night', 'rider' ], [ 'night', 'driver' ]) {
      my $max = $limits->[ slot_limit_index $pair->[ 0 ], $pair->[ 1 ] ]
         or next;

      for my $key (map { $pair->[ 0 ].'_'.$pair->[ 1 ].'_'.$_ } 0 .. $max - 1) {
         p_row $table, $self->$_alloc_slot_row
            ( $req, $page, $data, $dt, $key, $cno);
      }
   }

   for my $tuple (@{ $data->{events}->{ local_dt( $dt )->ymd } // [] }) {
      p_row $table, $self->$_alloc_event_row
         ( $req, $page, $data, $count++, $tuple, $cno );
   }

   for my $vevent (@{ $data->{vevents}->{ local_dt( $dt )->ymd } // [] }) {
      p_row $table, $self->$_alloc_vevent_row
         ( $req, $page, $data, $vevent, $cno );
   }

   return { class => 'embeded', value => $table };
};

my $_date_picker = sub {
   my ($self, $req, $rota_name, $rota_dt) = @_;

   my $href       =  $req->uri_for_action( $self->moniker.'/allocation' );
   my $local_dt   =  local_dt $rota_dt;
   my $form       =  {
      class       => 'day-selector-form',
      content     => {
         list     => [ {
            name  => 'rota_name',
            type  => 'hidden',
            value => $rota_name,
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
      form_name   => 'day-selector',
      href        => $href,
      type        => 'form', };

   $self->add_csrf_token( $req, $form );
   return $form;
};

my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

my $_initialise_journal = sub {
   my ($self, $req, $rota_dt, $vehicles) = @_;

   my $asset = $self->components->{asset}; my $journal = {};

   for my $type (keys %{ $vehicles }) {
      for my $vehicle (@{ $vehicles->{ $type } }) {
         my $tuple = $asset->find_last_keeper( $req, $rota_dt, $vehicle );

         $_add_journal->( $journal, $vehicle->vrn, $rota_dt, $tuple );
      }
   }

   return $journal;
};

my $_left_shift = sub {
   my ($self, $req, $rota_name, $date) = @_;

   my $actionp = $self->moniker.'/week_rota';

   $date = local_dt( $date )->truncate( to => 'day' )->subtract( days => 1 );

   return $req->uri_for_action( $actionp, [ $rota_name, $date->ymd ] );
};

my $_next_week_uri = sub {
   my ($self, $req, $method, $rota_name, $date, $params) = @_;

   my $actionp = $self->moniker."/${method}";

   $date = local_dt( $date )->truncate( to => 'day' )
                            ->add( days => $params->{cols} );

   return $req->uri_for_action( $actionp, [ $rota_name, $date->ymd ], $params );
};

my $_next_week = sub {
   my ($self, $req, $method, $name, $date, $params) = @_;

   my $href = $self->$_next_week_uri( $req, $method, $name, $date, $params );

   return p_link {}, 'next-week', $href, {
      class => 'next-rota', request => $req, value => locm $req, 'Next' };
};

my $_prev_week_uri = sub {
   my ($self, $req, $method, $rota_name, $date, $params) = @_;

   my $actionp = $self->moniker."/${method}";

   $date = local_dt( $date )->truncate( to => 'day' )
                            ->subtract( days => $params->{cols} );

   return $req->uri_for_action( $actionp, [ $rota_name, $date->ymd ], $params );
};

my $_prev_week = sub {
   my ($self, $req, $method, $name, $date, $params) = @_;

   my $href = $self->$_prev_week_uri( $req, $method, $name, $date, $params );

   return p_link {}, 'prev-week', $href, {
      class => 'prev-rota', request => $req, value => locm $req, 'Prev' };
};

my $_right_shift = sub {
   my ($self, $req, $rota_name, $date) = @_;

   my $actionp = $self->moniker.'/week_rota';

   $date = local_dt( $date )->truncate( to => 'day' )->add( days => 1 );

   return $req->uri_for_action( $actionp, [ $rota_name, $date->ymd ] );
};

my $_search_for_vehicle_events = sub {
   my ($self, $opts, $journal) = @_; my $vevents = {};

   $opts = { %{ $opts // {} } }; $journal //= {};

   my $event_rs = $self->schema->resultset( 'Event' );

   $opts->{prefetch} //=
      [ 'end_rota', 'location', 'owner', 'start_rota', 'vehicle' ];

   for my $vevent ($event_rs->search_for_vehicle_events( $opts )->all) {
      my $k = local_dt( $vevent->start_date )->ymd;

      push @{ $vevents->{ $k } //= [] }, $vevent;

      my $start = ($vevent->duration)[ 0 ];
      my $tuple = [ $vevent->owner, $vevent->location ];

      $_add_journal->( $journal, $vevent->vehicle->vrn, $start, $tuple );
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
      my $k = local_dt( $vreq->event->start_date )->ymd;

      for my $count (0 .. $tuple->[ 1 ] - 1) {
         push @{ $events->{ $k } //= [] }, [ $vreq->event, $vreq->type->name ];
      }
   }

   my $tport_rs = $self->schema->resultset( 'Transport' );

   $opts->{prefetch} = [ {
      'event' => [ 'end_rota', 'owner', 'start_rota' ] }, 'vehicle' ];

   for my $tport ($tport_rs->search_for_assigned_vehicles( $opts )->all) {
      my $k = local_dt( $tport->event->start_date )->ymd;
      my $vehicle = $tport->vehicle;

      push @{ $events->{ $k } //= [] }, [ $tport->event, $vehicle ];

      my $start = ($tport->event->duration)[ 0 ];
      my $tuple = [ $tport->event->owner ];

      $_add_journal->( $journal, $vehicle->vrn, $start, $tuple );
   }

   return $events;
};

my $_search_for_slots = sub {
   my ($self, $opts, $journal) = @_;

   $opts = { %{ $opts // {} } }; $journal //= {};

   my $slot_rs = $self->schema->resultset( 'Slot' ); my $slots = {};

   for my $slot (grep { $_->type_name->is_driver || $_->type_name->is_rider }
                 $slot_rs->search_for_slots( $opts )->all) {
      my $k = local_dt( $slot->start_date )->ymd.'_'.$slot->key;

      $slots->{ $k } = $slot; $slot->vehicle or next;

      my $start = ($slot->duration)[ 0 ]; my $tuple = [ $slot->operator ];

      $_add_journal->( $journal, $slot->vehicle->vrn, $start, $tuple );
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
         map  { my $href = $req->uri_for_action
                   ( 'day/day_rota', [ $rota_name, local_dt( $date )->ymd ] );
                $_onclick_relocate->( $page, $_->[ 0 ], $href ); $_ }
         map  { my $id = local_dt( $date )->ymd.'_'.$_->key;
                $_add_slot_tip->( $req, $page, $id ); [ $id, $_ ] }
         grep { $_->vehicle_requested and not $_->vehicle }
         map  { push @{ $slot_cache->[ $cno ] }, $_; $_ }
         grep { $_->date eq $date } @{ $slots };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => 'request-'.$_->[ 0 ],
                    title => locm( $req, 'Vehicle Request' ),
                    value => $_->[ 1 ]->name } ] }
         map  { my $href = $req->uri_for_action
                   ( 'asset/request_vehicle', [ $_->[ 0 ] ] );
                $_onclick_relocate->( $page, 'request-'.$_->[ 0 ], $href ); $_ }
         map  { $_add_vreq_tip->( $req, $page, $_ ); [ $_->uri, $_ ] }
         grep { $_->start_date eq $date } @{ $events };

      push @{ $row }, { class => 'narrow embeded', value => $table };
   }

   return $row;
};

my $_alloc_nav = sub {
   my ($self, $req, $rota_name, $rota_dt, $params) = @_;

   return {
      next => $self->$_next_week
         ( $req, 'allocation', $rota_name, $rota_dt, $params ),
      picker => $self->$_date_picker( $req, $rota_name, $rota_dt ),
      prev => $self->$_prev_week
         ( $req, 'allocation', $rota_name, $rota_dt, $params ),
      oplinks_style => 'max-width: '.($params->{cols} * 270).'px;'
   };
};

my $_alloc_query = sub {
   my ($self, $req, $page, $args, $params) = @_;

   my $moniker = $self->moniker;
   my $href = $req->uri_for_action( "${moniker}/allocation", $args );
   my $form = new_container 'display-control', $href, {
      class => 'standard-form display-control' };

   p_select $form, 'display_rows', $_select_number->( 10, $params->{rows} ), {
      class => 'single-digit submit', id => 'display_rows',
      label_field_class => 'control-label align-right' };

   $_onchange_submit->( $page, 'display_rows' );

   p_select $form, 'display_cols', $_select_number->( 10, $params->{cols} ), {
      class => 'single-digit submit', id => 'display_cols',
      label_field_class => 'control-label align-right' };

   $_onchange_submit->( $page, 'display_cols' );

   return { control => $form };
};

my $_allocation_page = sub {
   my ($self, $req, $rota_name, $rota_dt, $params) = @_;

   my $list = new_container { class => 'spreadsheet' };
   my $form = new_container {
      class => 'spreadsheet-key-table server', id => 'allocation-key' };
   my $page = {
      fields   => {
         nav   => $self->$_alloc_nav( $req, $rota_name, $rota_dt, $params ), },
      forms    => [ $list, $form ],
      off_grid => TRUE,
      template => [ 'none', 'custom/two-week-table' ],
      title    => locm $req, 'Vehicle Allocation',
   };

   $_onchange_submit->( $page, 'rota_date', 'day_selector' );
   return $page;
};

my $_week_rota_page = sub {
   my ($self, $req, $rota_name, $rota_dt) = @_;

   return {
      fields => {
         nav => {
            lshift => $self->$_left_shift( $req, $rota_name, $rota_dt ),
            next   => $self->$_next_week_uri
               ( $req, 'week_rota', $rota_name, $rota_dt, { cols => 7 } ),
            prev   => $self->$_prev_week_uri
               ( $req, 'week_rota', $rota_name, $rota_dt, { cols => 7 } ),
            rshift => $self->$_right_shift( $req, $rota_name, $rota_dt ),
         }, },
      rota       => {
         headers => $_week_rota_headers->( $req, $rota_dt ),
         name    => $rota_name,
         rows    => [] },
      template   => [ '/menu', 'custom/week-table' ],
      title      => $_week_rota_title->( $req, $rota_name, $rota_dt ), };
};

# Public methods
sub alloc_key : Dialog Role(rota_manager) {
   my ($self, $req) = @_;

   my $rota_date = $req->uri_params->( 0 );
   my $rota_dt = to_dt $rota_date;
   my $stash = $self->dialog_stash( $req );
   my $table = $stash->{page}->{forms}->[ 0 ] = new_container {
      class => 'key-table', type => 'table' };
   my $columns = [ qw( colour id name notes vrn ) ];
   my $vehicles = $self->schema->resultset( 'Vehicle' )->search_for_vehicles( {
      columns => $columns, service => TRUE } );
   my $assets = $self->components->{asset};
   my $keeper_dt = local_dt( $rota_dt->clone->subtract( seconds => 1 ) );

   $table->{headers} = $_alloc_key_headers->( $req, $keeper_dt );

   p_row $table, [ map { $_alloc_key_row->( $req, $assets, $keeper_dt, $_ ) }
                   $vehicles->all ];

   return $stash;
}

sub alloc_table : Dialog Role(rota_manager) {
   my ($self, $req) = @_;

   my $today = time2str '%Y-%m-%d';
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $req->uri_params->( 1, { optional => TRUE } ) // $today;
   my $cols = $req->uri_params->( 2, { optional => TRUE } ) // 7;
   my $rota_dt = to_dt $rota_date;
   my $opts = {
      after => $rota_dt->clone->subtract( days => 1 ),
      before => $rota_dt->clone->add( days => $cols ),
      rota_type => $self->$_find_rota_type( $rota_name )->id };
   my $vehicles = $self->$_search_for_vehicles();
   my $journal = $self->$_initialise_journal( $req, $rota_dt, $vehicles );
   my $events = $self->$_search_for_events( $opts, $journal );
   my $slots = $self->$_search_for_slots( $opts, $journal );
   my $vevents = $self->$_search_for_vehicle_events( $opts, $journal );
   my $data = {
      events => $events, journal => $journal, slots => $slots,
      vehicles => $vehicles, vevents => $vevents };
   my $stash = $self->dialog_stash( $req );
   my $page = $stash->{page};
   my $table = $page->{forms}->[ 0 ] = new_container {
      class => 'spreadsheet-table', type => 'table' };
   my $row = p_row $table;

   $table->{headers} = $_alloc_table_headers->( $req, $rota_dt, $cols );
   $page->{limits} = $self->config->slot_limits;
   $page->{moniker} = $self->moniker;
   $page->{rota_name} = $rota_name;
   $page->{rota_dt} = $rota_dt;

   p_cell $row, [ map { $self->$_alloc_cell( $req, $page, $data, $_ ) }
                  0 .. $cols - 1 ];

   p_js $page, 'behaviour.rebuild();';

   return $stash;
}

sub allocation : Role(rota_manager) {
   my ($self, $req) = @_;

   my $moniker = $self->moniker;
   my $today = time2str '%Y-%m-%d';
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $req->uri_params->( 1, { optional => TRUE } ) // $today;
   my $args = [ $rota_name, $rota_date ];
   my $params = $_alloc_query_params->( $req );
   my $rota_dt = to_dt $rota_date;
   my $page = $self->$_allocation_page( $req, $rota_name, $rota_dt, $params );
   my $list = $page->{forms}->[ 0 ];
   my $fields = $page->{fields};

   $_push_allocation_js->( $req, $page, $moniker, $rota_dt );

   $fields->{query} = $self->$_alloc_query( $req, $page, $args, $params );

   for my $rno (0 .. $params->{rows} - 1) {
      my $id = "allocation-row${rno}"; my $cols = $params->{cols};

      p_container $list, NUL, { class => 'allocation-row server', id => $id };

      my $date = local_dt( $rota_dt )->add( days => $cols * $rno )->ymd;
      my $args = [ $rota_name, $date, $cols ];
      my $href = $req->uri_for_action( "${moniker}/alloc_table", $args );
      my $opts = [ "${href}", $id ];

      p_js $page, js_server_config $id, 'load', 'request', $opts;
   }

   return $self->get_stash( $req, $page );
}

sub day_selector_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $rota_name = $req->body_params->( 'rota_name' );
   my $rota_date = $req->body_params->( 'rota_date' );
   my $rota_dt   = to_dt $rota_date;
   my $actionp   = $self->moniker.'/allocation';
   my $args      = [ $rota_name, local_dt( $rota_dt )->ymd ];
   my $location  = $req->uri_for_action( $actionp, $args );

   return { redirect => { location => $location } };
}

sub display_control_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $rota_name = $req->uri_params->( 0 );
   my $rota_date = $req->uri_params->( 1 );
   my $cols      = $req->body_params->( 'display_cols' );
   my $rows      = $req->body_params->( 'display_rows' );
   my $actionp   = $self->moniker.'/allocation';
   my $args      = [ $rota_name, $rota_date ];
   my $params    = { cols => $cols, rows => $rows };
   my $location  = $req->uri_for_action( $actionp, $args, $params );

   return { redirect => { location => $location } };
}

sub week_rota : Role(any) {
   my ($self, $req) = @_;

   my $today      =  time2str '%Y-%m-%d';
   my $rota_name  =  $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date  =  $req->uri_params->( 1, { optional => TRUE } ) // $today;
   my $rota_dt    =  to_dt $rota_date;
   my $page       =  $self->$_week_rota_page( $req, $rota_name, $rota_dt );
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

   $self->update_navigation_date( $req, local_dt $rota_dt );

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
