package App::Notitia::Model::WeekRota;

use utf8;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE HASH_CHAR NBSP NUL SPC TILDE TRUE );
use App::Notitia::DOM       qw( new_container p_cell p_container p_hidden p_item
                                p_js p_link p_list p_row p_select p_span
                                p_table );
use App::Notitia::Util      qw( assign_link calculate_distance contrast_colour
                                crow2road dialog_anchor js_server_config
                                js_submit_config js_togglers_config
                                local_dt locm make_tip
                                register_action_paths slot_claimed
                                slot_limit_index to_dt );
use Class::Null;
use Class::Usul::Time       qw( time2str );
use Scalar::Util            qw( blessed );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(App::Notitia::Role::Holidays);
with    q(App::Notitia::Role::DatePicker);

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

   ($stash->{page}->{template}->[ 1 ] // NUL) ne 'custom/two-week-table'
      and $stash->{page}->{location} = 'schedule';
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

my $_add_vevent_tip = sub {
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

my $_add_slot_js_dialog = sub {
   my ($req, $page, $jsid, $title, $args, $action) = @_;

   my $actionp = 'day/slot';
   my $href = $req->uri_for_action( $actionp, $args, { action => $action } );

   p_js $page, dialog_anchor $jsid, $href, {
      name  => "${action}-${jsid}",
      title => locm $req, (ucfirst $action).SPC.$title, };

   return;
};

my $_alloc_cell_event_headers = sub {
   my ($req, $cno) = @_; my @headings = qw( Event 択 Vehicle );

   return [ map { { colspan => $_ eq 'Event' ? 2 : 1, value => $_ } }
            @headings  ];
};

my $_alloc_cell_slot_headers = sub {
   my ($req, $cno) = @_; my @headings = qw( Name R C4 Vehicle );

   my $headers = [ map { { colspan => $_ eq 'Name' ? 2 : 1, value => $_ } }
                   @headings  ];

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

my $_insert_journal = sub {
   my ($journal, $vrn, $start, $tuple) = @_;

   my $list = $journal->{ $vrn } //= []; my $i = 0;

   while (my $entry = $list->[ $i ]) { $entry->{start} < $start and last; $i++ }

   my $location = $tuple->[ 1 ] && $tuple->[ 1 ]->coordinates ? $tuple->[ 1 ]
                : $tuple->[ 0 ];

   splice @{ $list }, $i, 0, { location => $location, start => $start };

   return;
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

my $_operators_vehicle_label = sub {
   my $slov = shift;

   return $slov && $slov->type eq '4x4' ? '4'
        : $slov && $slov->type eq 'car' ? 'C'
        : NBSP;
};

my $_operators_vehicle_link = sub {
   my ($req, $page, $rota_dt, $slot, $suppress) = @_;

   my $cell    = { class => 'table-cell-label narrow', value => NBSP };

   $suppress and return $cell;

   my $args    = [ $page->{rota_name}, local_dt( $rota_dt )->ymd, $slot->key ];
   my $tip     = locm $req, 'operators_vehicle_tip';
   my $actionp = 'day/operator_vehicle';
   my $id      = $slot->key.'_vehicle';

   if ($slot->operator eq $req->username and not $page->{disabled}) {
      p_link $cell, $id, HASH_CHAR, {
         class => 'windows', request => $req, tip => $tip,
         value => $_operators_vehicle_label->( $slot->operator_vehicle ),
      };

      p_js $page, dialog_anchor $id, $req->uri_for_action( $actionp, $args ), {
         name  => 'operator-vehicle' ,
         title => locm $req, 'operators_vehicle_title' };
   }
   else {
      $cell->{value} = $_operators_vehicle_label->( $slot->operator_vehicle );
   }

   return $cell;
};

my $_select_number = sub {
   my ($max, $selected) = @_;

   return [ map { [ $_ , $_, { selected => $selected eq $_? TRUE : FALSE } ] }
            1 .. $max ];
};

my $_slot_link_data = sub {
   my ($page, $dt, $dt_key, $slot) = @_;

   my $vehicle_type =  $slot->type_name eq 'driver' ? [ '4x4', 'car' ]
                    :  $slot->type_name eq 'rider'  ? 'bike' : undef;
   my $operator     =  $slot->operator;

   return { $dt_key => {
      name          => $slot->key,
      operator      => $operator,
      rota_dt       => $dt,
      rota_name     => $page->{rota_name},
      slov          => $slot->operator_vehicle,
      type          => $vehicle_type,
      vehicle       => $slot->vehicle,
      vehicle_req   => $slot->vehicle_requested } };
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

my $_union = sub {
   return [ @{ $_[ 0 ]->{ $_[ 1 ]->[ 0 ] } // [] },
            @{ $_[ 0 ]->{ $_[ 1 ]->[ 1 ] } // [] } ];
};

my $_vehicle_cell_style = sub {
   my $vehicle = shift; my $style = NUL;

   blessed $vehicle and $vehicle->colour
       and $style = 'background-color: '.$vehicle->colour.'; '
                  . 'color: '.contrast_colour( $vehicle->colour ).'; ';

   return $style;
};

my $_vehicle_or_request_list = sub {
   my $count = -1;

   return [ map { $count++; [ blessed $_ ? $_->name : $_, $count, {
      selected => $count == 0 ? TRUE : FALSE } ] }
            map { $_->[ 1 ] } @{ $_[ 0 ] } ];
};

my $_vehicle_or_request_select_cell = sub {
   my $tuples = shift;
   my $event = $tuples->[ 0 ]->[ 0 ];
   my $form = new_container { class => 'spreadsheet-fixed-form align-center' };

   p_select $form, 'vehicle', $_vehicle_or_request_list->( $tuples ), {
      class => 'spreadsheet-select-single togglers',
      id => "vehicles-${event}", label => NUL };

   return { class => 'table-cell-select narrow', value => $form };
};

my $_alloc_key_row = sub {
   my ($req, $assets, $keeper_dt, $vehicle) = @_; my $row = [];

   my $keeper = $assets->find_last_keeper( $req, $keeper_dt, $vehicle );
   my $style  = $_vehicle_cell_style->( $vehicle );

   p_cell $row, { style => $style, value => $vehicle->label };
   p_cell $row, { value => locm $req, $vehicle->type };
   p_cell $row, {
      value => $vehicle->model ? $vehicle->model->label( $req ) : NUL };
   p_cell $row, { class => 'narrow align-center',
                  value => $keeper ? $keeper->[ 0 ]->region : NUL };
   p_cell $row, { value => $keeper ? $keeper->[ 0 ]->label : NUL };

   my $location = $keeper ? $keeper->[ 0 ]->location : NUL;

   $location and $location .= ' ('.$keeper->[ 0 ]->outer_postcode.')';

   p_cell $row, { value => $location };

   return $row;
};

my $_alloc_key_headers = sub {
   my ($req, $keeper_dt) = @_;

   my @headings = ( 'Vehicle', 'Type', 'Model', 'R',
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

my $_alloc_cell_event = sub {
   my ($req, $page, $row, $event, $style, $id) = @_;

   my $text = $event->event_type eq 'person' ? 'Fund Raising Event'
            : $event->event_type eq 'training' ? 'Training Event'
            : 'Vehicle Event';

   my $cell = p_cell $row, {
      class   => 'spreadsheet-fixed-cell table-cell-label server tips',
      colspan => 2,
      name    => $event->uri,
      title   => locm( $req, $text ).SPC.TILDE.SPC.NBSP,
   };

   $_add_event_tip->( $req, $page, $event );

   my $href = $req->uri_for_action( 'event/event_summary', [ $event->uri ] );

   p_link $cell, NUL, $href, {
      class => 'label-column', tip => NUL, value => $event->name };

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
      and $style = 'background-color: '.$vehicle->colour.';'
                 . 'color: '.contrast_colour( $vehicle->colour ).';';
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
         map  { $_add_vevent_tip->( $req, $page, $_ ); [ $_->uri, $_ ] }
         grep { $_->vehicle->vrn eq $vehicle->vrn }
         grep { $_->start_date eq $date } @{ $events };

      push @{ $row }, { class => 'narrow embeded', value => $table };
   }

   return $row;
};

# Private methods
my $_max_controllers = sub {
   my $self = shift;
   my $limits = $self->config->slot_limits;
   my $max_day = $limits->[ slot_limit_index 'day', 'controller' ];
   my $max_night
      = $limits->[ slot_limit_index 'night', 'controller' ];

   return wantarray             ? [ $max_day, $max_night ]
        : $max_day > $max_night ? $max_day : $max_night;
};

my $_alloc_cell_controller_headers = sub {
   my ($self, $req, $cno) = @_;

   my @headings = map { 'Controller' } 0 .. $self->$_max_controllers - 1;

   return [ map { { value => $_ } } @headings  ];
};

my $_alloc_cell_controller_row = sub {
   my ($self, $req, $page, $data, $dt, $shift) = @_; my $row = [];

   my $local_ymd = local_dt( $dt )->ymd;
   my $max = ($self->$_max_controllers)[ $shift eq 'day' ? 0 : 1 ] // 0;

   for my $subslot (0 .. $self->$_max_controllers - 1) {
      my $slot_key = "${shift}_controller_${subslot}";
      my $dt_key = "${local_ymd}_${slot_key}";
      my $slot = $data->{slots}->{ $dt_key } // Class::Null->new;
      my $link_data = $_slot_link_data->( $page, $dt, $dt_key, $slot );
      my $cell =  p_cell $row, $self->components->{day}->slot_link
         ( $req, $page, $link_data, $dt_key, 'controller' );

      $cell->{class} = 'spreadsheet-fixed-cell table-cell-label';
      $cell->{colspan} = 1;

      if ($subslot > $max
          or $shift eq 'day' and $self->is_working_day( local_dt $dt )) {
         $cell->{value}->{value} = NBSP; $cell->{value}->{tip} = NBSP;
      }

      my $title  = 'Controller Slot';
      my $args   = [ $page->{rota_name}, $local_ymd, $slot_key ];
      my $action =  slot_claimed $link_data->{ $dt_key } ? 'yield' : 'claim';

      $_add_slot_js_dialog->( $req, $page, $dt_key, $title, $args, $action );
   }

   return $row;
};

my $_alloc_cell_event_row = sub {
   my ($self, $req, $page, $data, $count, $tuples, $cno) = @_; my $row = [];

   my $event = $tuples->[ 0 ]->[ 0 ];

   $_alloc_cell_event->( $req, $page, $row, $event, NUL, $event->uri );

   p_cell $row, $_vehicle_or_request_select_cell->( $tuples );

   my $id = "vehicles-${event}"; p_js $page, js_togglers_config $id, 'change',
      'showSelected', [ $id, scalar @{ $tuples } ];

   my $cell = p_cell $row, {
      class => 'table-cell-embeded narrow' };
   my $list = p_list $cell, NUL, [], { class => 'table-cell-list' };
   my $index = 0;

   for my $v_or_r (map { $_->[ 1 ] } @{ $tuples }) {
      my $action  = blessed $v_or_r ? 'unassign' : 'assign';
      my $vehicle = $action eq 'unassign' ? $v_or_r : undef;
      my $value   = $action eq 'unassign' ? $v_or_r->name : ucfirst $v_or_r;
      my $type    = $action eq 'unassign' ? $v_or_r->type : $v_or_r;
      my $args    = [ $event->uri, $page->{rota_date} ];
      my $params  = { action => $action, mode => 'slow',
                      type   => $type, vehicle => $vehicle };
      my $href    = $req->uri_for_action( 'asset/assign', $args, $params );

      p_link $list, "${id}-${index}", HASH_CHAR, {
         class => $index == 0 ? 'table-cell-link windows'
                : 'table-cell-link windows hidden',
         style => $_vehicle_cell_style->( $v_or_r ),
         tip   => NUL,
         value => $value };

      p_js $page, dialog_anchor "${id}-${index}", $href, {
         name  => "${action}-vehicle",
         title => locm $req, ucfirst "${action} Vehicle" };
      $index++;
   }

   return $row;
};

my $_alloc_cell_slot_row = sub {
   my ($self, $req, $page, $data, $dt, $slot_key, $cno) = @_; my $row = [];

   my $local_ymd = local_dt( $dt )->ymd;
   my $dt_key = "${local_ymd}_${slot_key}";
   my $slot = $data->{slots}->{ $dt_key } // Class::Null->new;
   my ($shift, $slot_type) = split m{ _ }mx, $slot_key;
   my $suppress = $shift eq 'day' && $self->is_working_day( local_dt $dt )
                ? TRUE : FALSE;

   $cno == 0 and p_cell $row, {
      class => 'rota-header align-center',
      value => locm $req, "${slot_key}_abbrv" };

   my $operator     =  $slot->operator;
   my $link_data    =  $_slot_link_data->( $page, $dt, $dt_key, $slot );
   my $cell         =  p_cell $row, $self->components->{day}->slot_link
      ( $req, $page, $link_data, $dt_key, $slot_type );

   $cell->{class}   =  'spreadsheet-fixed-cell table-cell-label';

   if ($suppress) {
      $cell->{value}->{value} = NBSP; $cell->{value}->{tip} = NUL;
   }

   my $args   = [ $page->{rota_name}, $local_ymd, $slot_key ];
   my $title  = $slot_type eq 'driver' ? 'Driver Slot' : 'Rider Slot';
   my $action = slot_claimed $link_data->{ $dt_key } ? 'yield' : 'claim';

   $_add_slot_js_dialog->( $req, $page, $dt_key, $title, $args, $action );

   p_cell $row, {
      class => 'table-cell-label narrow',
      value => $suppress ? NBSP : $operator->id ? $operator->region : NBSP };
   p_cell $row, $_operators_vehicle_link->( $req, $page, $dt, $slot, $suppress);

   if (not $suppress and $operator->id and $slot->vehicle_requested) {
      $link_data->{ $dt_key }->{mode} = 'slow';
      $link_data->{ $dt_key }->{name} = $dt_key;

      my $cell = p_cell $row,
         assign_link $req, $page, $args, $link_data->{ $dt_key };

      $cell->{class} = 'table-cell-label narrow';
   }
   else { p_cell $row, { class => 'table-cell-label narrow', value => NBSP } }

   return $row;
};

my $_alloc_cell_vevent_row = sub {
   my ($self, $req, $page, $data, $vevent, $cno) = @_; my $row = [];

   $_alloc_cell_event->( $req, $page, $row, $vevent, NUL, $vevent->uri );

   $_add_vevent_tip->( $req, $page, $vevent );

   p_cell $row, { value => NUL }; p_cell $row, { value => NUL };

   my $vehicle = $vevent->vehicle;
   my $style = $_vehicle_cell_style->( $vehicle );

   p_cell $row, {
      class => 'table-cell-label', style => $style, value => $vehicle->name };

   return $row;
};

my $_alloc_cell_events = sub {
   my ($data, $dt) = @_; my $events = {};

   for my $tuple (@{ $data->{events}->{ local_dt( $dt )->ymd } // [] }) {
      push @{ $events->{ $tuple->[ 0 ]->uri } //= [] }, $tuple;
   }

   return $events;
};

my $_alloc_cell = sub {
   my ($self, $req, $page, $data, $cno) = @_; my $tables = new_container;

   my $dt     = $page->{rota_dt}->clone->add( days => $cno );
   my $events = $_alloc_cell_events->( $data, $dt );
   my $table  = p_table $tables, { class => 'embeded' };
   my $count  = 0;

   $table->{headers} = $_alloc_cell_event_headers->( $req, $cno );

   for my $uri (sort keys %{ $events }) {
      p_row $table, $self->$_alloc_cell_event_row
         ( $req, $page, $data, $count++, $events->{ $uri }, $cno );
   }

   while ($count++ < 4) {
      p_row $table, [ map { {
         class => $_ == 0 ? 'table-cell-label'
                : $_ == 1 ? 'table-cell-select narrow'
                :           'spreadsheet-fixed-cell table-cell-label',
         colspan => $_ == 0 ? 2 : 1, value => NBSP } }
                      0 .. 2 ];
   }

   $table = p_table $tables, { class => 'embeded' };

   $table->{headers} = $self->$_alloc_cell_controller_headers( $req, $cno );

   p_row $table, $self->$_alloc_cell_controller_row
      ( $req, $page, $data, $dt, 'day' );
   p_row $table, $self->$_alloc_cell_controller_row
      ( $req, $page, $data, $dt, 'night' );

   $table = p_table $tables, { class => 'embeded' };

   $table->{headers} = $_alloc_cell_slot_headers->( $req, $cno );

   my $limits = $page->{limits};

   for my $pair ([ 'day',   'rider' ], [ 'day',   'driver' ],
                 [ 'night', 'rider' ], [ 'night', 'driver' ]) {
      my $max = $limits->[ slot_limit_index $pair->[ 0 ], $pair->[ 1 ] ]
         or next;

      for my $key (map { $pair->[ 0 ].'_'.$pair->[ 1 ].'_'.$_ } 0 .. $max - 1) {
         p_row $table, $self->$_alloc_cell_slot_row
            ( $req, $page, $data, $dt, $key, $cno);
      }
   }

   for my $vevent (@{ $data->{vevents}->{ local_dt( $dt )->ymd } // [] }) {
      p_row $table, $self->$_alloc_cell_vevent_row
         ( $req, $page, $data, $vevent, $cno );
   }

   return { class => 'embeded', value => $tables };
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

         $_insert_journal->( $journal, $vehicle->vrn, $rota_dt, $tuple );
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

      $_insert_journal->( $journal, $vevent->vehicle->vrn, $start, $tuple );
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

      $_insert_journal->( $journal, $vehicle->vrn, $start, $tuple );
   }

   return $events;
};

my $_search_for_slots = sub {
   my ($self, $opts, $journal) = @_;

   $opts = { %{ $opts // {} } }; $journal //= {};

   my $slot_rs = $self->schema->resultset( 'Slot' ); my $slots = {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $k = local_dt( $slot->start_date )->ymd.'_'.$slot->key;

      $slots->{ $k } = $slot; $slot->vehicle or next;

      my $start = ($slot->duration)[ 0 ]; my $tuple = [ $slot->operator ];

      $_insert_journal->( $journal, $slot->vehicle->vrn, $start, $tuple );
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

   my $href = $req->uri_for_action( $self->moniker.'/allocation' );

   return {
      next => $self->$_next_week
         ( $req, 'allocation', $rota_name, $rota_dt, $params ),
      picker => $self->date_picker
         ( $req, 'paddle', $rota_name, local_dt( $rota_dt ), $href ),
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

   $self->add_csrf_token( $req, $form );

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
      title    => locm $req, 'vehicle_allocation_title',
   };

   $self->date_picker_js( $page );

   return $page;
};

my $_find_event_or_slot = sub {
   my ($self, $req, $is_slot, $args) = @_; my $object;

   my $schema = $self->schema;

   if ($is_slot) {
      my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $args->[ 2 ], 3;

      my $rs     = $schema->resultset( 'Person' );
      my $person = $rs->find_by_shortcode( $req->username );
      my $shift  = $person->find_shift
         ( $args->[ 0 ], to_dt( $args->[ 1 ] ), $shift_type );

      $object = $person->find_slot( $shift, $slot_type, $subslot );
   }
   else {
      $object = $schema->resultset( 'Event' )->find_event_by( $args->[ 0 ] );
   }

   return $object;
};

my $_get_all_the_data = sub {
   my ($self, $req, $rota_name, $rota_dt, $cols) = @_;

   my $opts = {
      after => $rota_dt->clone->subtract( days => 1 ),
      before => $rota_dt->clone->add( days => $cols ),
      rota_type => $self->$_find_rota_type( $rota_name )->id };
   my $vehicles = $self->$_search_for_vehicles();
   my $journal = $self->$_initialise_journal( $req, $rota_dt, $vehicles );
   my $events = $self->$_search_for_events( $opts, $journal );
   my $slots = $self->$_search_for_slots( $opts, $journal );
   my $vevents = $self->$_search_for_vehicle_events( $opts, $journal );

   return {
      events => $events,
      journal => $journal,
      slots => $slots,
      vehicles => $vehicles,
      vevents => $vevents,
   };
};

my $_vehicle_label = sub {
   my ($self, $data, $vehicle) = @_;

   my $list = $data->{journal}->{ $vehicle->vrn };
   my $location = $_find_location->( $list, $data->{start} );
   my $distance = calculate_distance $location, $data->{assignee}
      or return $vehicle->name;
   my $df = $self->config->distance_factor;

   $distance = crow2road $distance, $df->[ 0 ];

   return $vehicle->name." (${distance} mls)";
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
sub alloc_key : Dialog Role(controller) Role(driver) Role(rider)
   Role(rota_manager) {
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

sub alloc_table : Dialog Role(controller) Role(driver) Role(rider)
   Role(rota_manager) {
   my ($self, $req) = @_;

   my $today = time2str '%Y-%m-%d';
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $req->uri_params->( 1, { optional => TRUE } ) // $today;
   my $cols = $req->uri_params->( 2, { optional => TRUE } ) // 7;
   my $rota_dt = to_dt $rota_date;
   my $data = $self->$_get_all_the_data( $req, $rota_name, $rota_dt, $cols );
   my $stash = $self->dialog_stash( $req );
   my $page = $stash->{page};
   my $table = $page->{forms}->[ 0 ] = new_container {
      class => 'spreadsheet-table', type => 'table' };
   my $row = p_row $table;

   $table->{headers} = $_alloc_table_headers->( $req, $rota_dt, $cols );
   $page->{limits} = $self->config->slot_limits;
   $page->{moniker} = $self->moniker;
   $page->{rota_name} = $rota_name;
   $page->{rota_date} = $rota_date;
   $page->{rota_dt} = $rota_dt;

   p_cell $row, [ map { $self->$_alloc_cell( $req, $page, $data, $_ ) }
                  0 .. $cols - 1 ];

   p_js $page, 'behaviour.rebuild();';

   return $stash;
}

sub allocation : Role(controller) Role(driver) Role(rider)
   Role(rota_manager) {
   my ($self, $req) = @_;

   my $today = time2str '%Y-%m-%d';
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $req->uri_params->( 1, { optional => TRUE } ) // $today;
   my $args = [ $rota_name, $rota_date ];
   my $params = $_alloc_query_params->( $req );
   my $rota_dt = to_dt $rota_date;
   my $page = $self->$_allocation_page( $req, $rota_name, $rota_dt, $params );
   my $list = $page->{forms}->[ 0 ];
   my $fields = $page->{fields};
   my $moniker = $self->moniker;

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

sub day_selector_action : Role(controller) Role(driver) Role(rider)
   Role(rota_manager) {
   my ($self, $req) = @_;

   return $self->date_picker_redirect( $req, $self->moniker.'/allocation' );
}

sub display_control_action : Role(controller) Role(driver) Role(rider)
   Role(rota_manager) {
   my ($self, $req) = @_;

   my $rota_name = $req->uri_params->( 0 );
   my $rota_date = $req->uri_params->( 1 );
   my $rows      = $req->body_params->( 'display_rows' );
   my $actionp   = $self->moniker.'/allocation';
   my $args      = [ $rota_name, $rota_date ];
   my $params    = { rows => $rows };
   my $location  = $req->uri_for_action( $actionp, $args, $params );

   return { redirect => { location => $location } };
}

sub filter_vehicles {
   my ($self, $req, $args, $tuples) = @_; my $r = [];

   my $assigner = $req->username; my $is_slot = TRUE;

   try   { $self->$_find_rota_type( $args->[ 0 ] ) }
   catch { $is_slot = FALSE };

   for my $tuple (@{ $tuples }) {
      my $vehicle = $tuple->[ 1 ];

      if ($is_slot) {
         $vehicle->is_slot_assignment_allowed
            ( $args->[ 0 ], to_dt( $args->[ 1 ] ), $args->[ 2 ], $assigner )
            and push @{ $r }, $tuple;
      }
      else {
         $vehicle->is_event_assignment_allowed( $args->[ 0 ], $assigner )
            and push @{ $r }, $tuple;
      }
   }

   my $rota_name = $is_slot ? $args->[ 0 ] : 'main';
   my $rota_dt = to_dt( $args->[ 1 ] );
   my $object = $self->$_find_event_or_slot( $req, $is_slot, $args );
   my $data = $self->$_get_all_the_data( $req, $rota_name, $rota_dt, 7 );
   my $opts = { assignee => $is_slot ? $object->operator : $object->owner,
                journal => $data->{journal},
                start => ($object->duration)[ 0 ], };

   return [ map {
      [ $self->$_vehicle_label( $opts, $_->[ 1 ] ), $_->[ 1 ], $_->[ 2 ] ] }
            @{ $r } ];
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
# coding: utf-8
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
