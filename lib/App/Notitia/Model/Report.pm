package App::Notitia::Model::Report;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_cell p_container p_date
                                p_hidden p_js p_link p_list p_row p_select
                                p_table );
use App::Notitia::Util      qw( js_submit_config local_dt locd locm make_tip
                                now_dt to_dt register_action_paths
                                slot_limit_index uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( sum throw );
use Scalar::Util            qw( blessed weaken );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

# Public attributes
has '+moniker' => default => 'report';

register_action_paths
   'report/customers' => 'customer-report',
   'report/controls' => 'report-controls',
   'report/deliveries' => 'delivery-report',
   'report/people_meta' => 'people-meta-report',
   'report/people' => 'people-report',
   'report/slots' => 'slots-report',
   'report/vehicles' => 'vehicles-report';

# Construction
my $_download_format = sub {
   my ($self, $req, $stash, $format) = @_;

   delete $stash->{page}->{literal_js}; $stash->{view} = $format;

   return;
};

around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   my $format = $req->query_params->( 'format', { optional => TRUE } );

   $format and $self->$_download_format( $req, $stash, $format );

   return $stash;
};

my @ROLES = qw( active rider controller driver fund_raiser );

# Private functions
my $_localise = sub {
   my $v = shift; my $class;

   defined $v and $class = blessed $v and $class eq 'DateTime'
       and $v = local_dt $v;

   return $v;
};

my $_select_periods = sub {
   return
      [ 'Last month', 'last-month' ],
      [ 'Last quarter', 'last-quarter' ],
      [ 'Last week', 'last-week' ],
      [ 'Last year', 'last-year' ],
      [ 'Rolling month', 'rolling-month' ],
      [ 'Rolling quarter', 'rolling-quarter' ],
      [ 'Year to date', 'year-to-date' ];
};

my $_compare_counts = sub {
   my ($data, $k1, $k2, $index) = @_;

   return $data->{ $k2 }->{count}->[ $index ]
      <=> $data->{ $k1 }->{count}->[ $index ];
};

my $_delivery_columns = sub {
   return qw( controller created customer delivered dropoff notes
              original_priority pickup priority requested );
};

my $_stage_columns = sub {
   my $prefix = shift;
   my @cols = qw( beginning called collected collection_eta created delivered
                  ending on_station operator vehicle );

   return $prefix ? map { "${prefix}_${_}" } @cols : @cols;
};

my $_delivery_headers = sub {
   return [ map { { value => $_ } } $_delivery_columns->(),
            $_stage_columns->( 'leg1' ), $_stage_columns->( 'leg2' ) ];
};

my $_delivery_row = sub {
   my ($req, $delivery) = @_; my @stages = $delivery->legs->all;

   while (@stages > 2) { splice @stages, 1, 1 }

   my $first_stage = $stages[ 0 ] // Class::Null->new;
   my $last_stage = $stages[ 1 ] // Class::Null->new;
   my @delivery_cols = map {
      { value => $_localise->( $delivery->$_() ) } } $_delivery_columns->();
   my @first_stage_cols = map {
      { value => $_localise->( $first_stage->$_() ) } } $_stage_columns->();
   my @last_stage_cols = map {
      { value => $_localise->( $last_stage->$_() ) } } $_stage_columns->();

   return [ @delivery_cols, @first_stage_cols, @last_stage_cols ];
};

my $_display_period = sub {
   my $opts = shift; my $period = $opts->{period} // NUL;

   return
      [ map { $_->[ 1 ] eq $period and $_->[ 2 ] = { selected => TRUE }; $_ }
        [ NUL, NUL ], $_select_periods->() ];
};

my $_dl_links = sub {
   my ($req, $type, $opts) = @_; my $links = [];

   my $after = local_dt( $opts->{after} )->ymd;
   my $before = local_dt( $opts->{before} )->ymd;
   my $csv_opts = {
      class => 'button', container_class => 'right',
      download => "${type}-report_${after}_${before}.csv", request => $req,
      tip => locm $req, 'Download the [_1] report as a CSV file', $type };
   my $href = $req->uri->clone;
   my %query = $href->query_form;

   exists $query{format} or $href->query_form( %query, format => 'csv' );
   p_link $links, 'download_csv', $href, $csv_opts;

   return $links;
};

my $_exclusive_date_range = sub {
   my $opts = shift; $opts = { %{ $opts } }; delete $opts->{period};

   $opts->{after} = $opts->{after}->clone->truncate( to => 'day' )
                                         ->subtract( seconds => 1 );
   $opts->{before} = $opts->{before}->clone->add( days => 1 )
                                           ->truncate( to => 'day' );
   return $opts;
};

my $_expand_range = sub {
   my $period = shift; my $now = now_dt;

   my $after = local_dt $now; my $before = local_dt $now;

   if ($period eq 'last-month') {
      $after = $after->subtract( months => 1 )->truncate( to => 'month' ) ;
      $before = $after->clone->add( months => 1 )->subtract( days => 1 ) ;
   }
   elsif ($period eq 'last-quarter') {
      $after = $after->subtract( months => 3 )->truncate( to => 'month' ) ;
      $before = $after->clone->add( months => 3 )->subtract( days => 1 ) ;
   }
   elsif ($period eq 'last-week') {
      $after = $after->subtract( weeks => 1 )->truncate( to => 'week' ) ;
      $before = $after->clone->add( weeks => 1 )->subtract( days => 1 ) ;
   }
   elsif ($period eq 'last-year') {
      $after = $after->subtract( years => 1 )->truncate( to => 'year' ) ;
      $before = $after->clone->add( years => 1 )->subtract( days => 1 ) ;
   }
   elsif ($period eq 'rolling-month') {
      $after = $after->subtract( months => 1 );
      $before = $before->subtract( days => 1 );
   }
   elsif ($period eq 'rolling-quarter') {
      $after = $after->subtract( months => 3 );
      $before = $before->subtract( days => 1 );
   }
   elsif ($period eq 'year-to-date') {
      $after = $after->truncate( to => 'year' );
      $before = $before->subtract( days => 1 );
   }

   return $after->ymd, $before->ymd;
};

my $_find_insertion_pos = sub {
   my ($data, $dt) = @_; my $i = 0;

   $i++ while (defined $data->[ $i ] and $data->[ $i ]->{date} < $dt);

   return $i;
};

my $_get_bucket = sub {
   my ($df, $data, $lookup, $dt) = @_; my $key = $df->( local_dt $dt );

   exists $lookup->{ $key } and return $lookup->{ $key };

   my $bucket = $lookup->{ $key } = { date => $dt, key => $key };

   splice @{ $data }, $_find_insertion_pos->( $data, $dt ), 0, $bucket;

   return $bucket;
};

my $_get_date_function = sub {
   my ($req, $opts) = @_; weaken $req;

   my $after = $opts->{after};
   my $before = $opts->{before};
   my $drtn = local_dt( $after )->delta_md( local_dt $before );

   if ($drtn->years > 2 or ($drtn->years == 2
       and ($drtn->months > 0 or $drtn->weeks > 0 or $drtn->days > 0))) {
      return sub { $_[ 0 ] ? $_[ 0 ]->year : 'year' };
   }
   elsif ($drtn->years == 2 or ($drtn->years == 1
          and ($drtn->months > 0 or $drtn->weeks > 0 or $drtn->days > 0))) {
      return sub {
             $_[ 0 ] ? 'Q'.$_[ 0 ]->quarter.SPC.$_[ 0 ]->year : 'quarter' };
   }
   elsif ($drtn->years == 1 or $drtn->months > 3
          or ($drtn->months == 3 and ($drtn->weeks > 0 or $drtn->days > 0))) {
      return sub { $_[ 0 ] ? $_[ 0 ]->month_name.SPC.$_[ 0 ]->year : 'month' };
   }
   elsif ($drtn->months >= 2
          or ($drtn->months == 1 and ($drtn->weeks > 0 or $drtn->days > 0))) {
      return sub {
         my $dt = shift; $dt or return 'week';

         $dt = $dt->clone->truncate( to => 'week' );

         return 'Wk'.$dt->week_number.SPC.locd( $req, $dt );
      };
   }

   return sub { $_[ 0 ] ? locd( $req, $_[ 0 ] ) : 'day' };
};

my $_inc_bucket = sub {
   my ($bucket, $person, $index) = @_; my @roles = ('active', $person->roles);

   for my $role (map { $bucket->{ $_ } //= [ 0, 0, 0 ]; $_ } @roles) {
      $bucket->{ $role }->[ $index ]++;
   }

   return;
};

my $_inc_resource_count = sub {
   my ($slot, $rec) = @_; my $index;

   $slot->type_name->is_controller and $index = 0;
   $slot->type_name->is_rider and $index = 1;
   $slot->type_name->is_driver and $index = 2;
   defined $index or return;
   $rec->{count}->[ $index ] //= 0; $rec->{count}->[ $index ]++;
   return;
};

my $_link_args = sub {
   my ($name, $basis, $dt) = @_;

   my $from = local_dt $dt; my $to = local_dt $dt;

   if ($basis eq 'year') {
      $from = $from->truncate( to => 'year' );
      $to = $to->truncate( to => 'year' )
               ->add( years => 1 )->subtract( days => 1 );
   }
   elsif ($basis eq 'quarter') {
      $from = $from->set( month => 3 * ($from->quarter - 1) + 1 )
                   ->truncate( to => 'month' );
      $to = $from->clone->add( months => 3 )->subtract( days => 1 );
   }
   elsif ($basis eq 'month') {
      $from = $from->truncate( to => 'month' );
      $to = $to->truncate( to => 'month' )
               ->add( months => 1 )->subtract( days => 1 );
   }
   elsif ($basis eq 'week') {
      $from = $from->truncate( to => 'week' );
      $to = $to->truncate( to => 'week' )
               ->add( weeks => 1 )->subtract( days => 1 );
   }

   return [ $name, $from->ymd, $to->ymd ];
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

my $_onchange_submit = sub {
   my ($page, $k) = @_;

   p_js $page, js_submit_config $k,
      'change', 'submitForm', [ 'date_control', 'date-control' ];

   return;
};

my $_push_date_controls = sub {
   my ($page, $opts) = @_; my $form = $page->{forms}->[ 0 ];

   p_date $form, 'after_date', $opts->{after}, {
      class => 'date-field submit', label_field_class => 'control-label' };
   p_hidden $form, 'prev_after_date', $opts->{after};
   $_onchange_submit->( $page, 'after_date' );

   p_date $form, 'before_date', $opts->{before}, {
      class => 'date-field submit', label_field_class => 'control-label' };
   p_hidden $form, 'prev_before_date', $opts->{before};
   $_onchange_submit->( $page, 'before_date' );

   p_select $form, 'display_period', $_display_period->( $opts ), {
      class => 'narrow-field submit', id => 'period', label_class => 'right',
      label_field_class => 'control-label' };
   $_onchange_submit->( $page, 'period' );

   return;
};

my $_report_headers = sub {
   my ($req, $type, $to, $from) = @_; $from //= 0;

   return [ map { { value => locm $req, "${type}_report_heading_${_}" } }
            $from .. $to ];
};

my $_report_row = sub {
   my ($label, $rec, $max_count) = @_; my $counts = $rec->{count};

   return [ { value => $label },
            map { { class => 'align-right', value => $counts->[ $_ ] // 0 } }
            0 .. $max_count ];
};

my $_slot_utilisation = sub {
   my ($rec, $_lookup_expected) = @_;

   my $expected = $_lookup_expected->( $rec );
   my $total = sum map { defined $_ ? $_ : 0 } @{ $rec->{count} };

   $rec->{count}->[ 3 ] = int( 100 * $total / $expected ).'%';
   return $rec;
};

my $_sum_counts = sub {
   my ($data, $k, $index) = @_; my $counts = $data->{ $k }->{count};

   $counts->[ $index ] = sum map { defined $_ ? $_ : 0 } @{ $counts };

   return $k;
};

my $_people_meta_header_link = sub {
   my ($req, $moniker, $opts, $col) = @_;

   my $name = "people_meta_summary_heading_${col}";
   my $from = local_dt( $opts->{after} )->ymd;
   my $to   = local_dt( $opts->{before} )->ymd;
   my $args = [ $ROLES[ $col - 1 ], $from, $to ];
   my $href = uri_for_action $req,"${moniker}/people_meta", $args;

   return { value => f_link $name, $href, { request => $req } };
};

my $_people_meta_report_title = sub {
   my ($req, $name) = @_;

   my $label = ucfirst $name; $label =~ s{ [_] }{ }gmx;

   $name ne 'all'
      and return locm $req, 'people_meta_summary_report_title', $label;

   return locm $req, 'people_meta_report_title';
};

my $_people_meta_table = sub {
   my ($req, $form, $data, $name) = @_;

   my $headers = $_report_headers->( $req, 'people_meta', 3 );
   my $table = p_table $form, { headers => $headers };

   p_row $table, [ map { $_report_row->( $_->{key}, $_, 2 ) }
                   map { { count => $_->{ $name }, key => $_->{key} } }
                      @{ $data } ];
   return $table;
};

# Private methods
my $_counts_by_person = sub {
   my ($self, $opts) = @_;

   $opts = $_exclusive_date_range->( $opts ); delete $opts->{rota_name};

   my $slot_rs = $self->schema->resultset( 'Slot' );
   my $participent_rs = $self->schema->resultset( 'Participent' );
   my $attendees = $participent_rs->search_for_attendees( $opts );
   my $data = {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $person = $slot->operator;
      my $rec = $data->{ $person->shortcode } //= { person => $person };

      $_inc_resource_count->( $slot, $rec );
   }

   for my $person (map { $_->participent } $attendees->all) {
      my $rec = $data->{ $person->shortcode } //= { person => $person };

      $rec->{count}->[ 3 ] //= 0; $rec->{count}->[ 3 ]++;
   }

   return $data;
};

my $_counts_by_slot = sub {
   my ($self, $req, $opts) = @_; my $df = $_get_date_function->( $req, $opts );

   $opts = $_exclusive_date_range->( $opts ); delete $opts->{rota_name};

   my $slot_rs = $self->schema->resultset( 'Slot' );
   my $data = []; my $lookup = {}; $opts->{order_by} = 'rota.date';

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $key = $df->( my $date = local_dt $slot->date );
      my $rec = { date => $date };

      if (exists $lookup->{ $key }) { $rec = $lookup->{ $key } }
      else { $lookup->{ $key } = $rec; push @{ $data }, $rec }

      $rec->{ $date->ymd.'_'.$slot->key } = $slot;
   }

   for my $rec (@{ $data }) {
      for my $key (grep { $_ ne 'count' && $_ ne 'date' } keys %{ $rec }) {
         $_inc_resource_count->( $rec->{ $key }, $rec );
      }
   }

   return $data;
};

my $_counts_by_vehicle = sub {
   my ($self, $opts) = @_;

   $opts = $_exclusive_date_range->( $opts ); delete $opts->{rota_name};

   my $slot_rs = $self->schema->resultset( 'Slot' );
   my $tport_rs = $self->schema->resultset( 'Transport' );
   my $tports = $tport_rs->search_for_assigned_vehicles( $opts );
   my $data = {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $vehicle = $slot->vehicle or next;
      my $rec = $data->{ $vehicle->vrn } //= { vehicle => $vehicle };
      my $index;

      $slot->shift->type_name->is_day and $index = 0;
      $slot->shift->type_name->is_night and $index = 1;
      defined $index or next;
      $rec->{count}->[ $index ] //= 0; $rec->{count}->[ $index ]++;
   }

   for my $vehicle (map { $_->vehicle } $tports->all) {
      my $rec = $data->{ $vehicle->vrn } //= { vehicle => $vehicle };

      $rec->{count}->[ 2 ] //= 0; $rec->{count}->[ 2 ]++;
   }

   return $data;
};

my $_counts_of_people = sub {
   my ($self, $req, $opts) = @_; my $df = $_get_date_function->( $req, $opts );

   $opts = $_exclusive_date_range->( $opts ); delete $opts->{role_name};

   my $person_rs = $self->schema->resultset( 'Person' );
   my $data = []; my $lookup = {}; my $totals = {};

   for my $person ($person_rs->search_by_period( $opts )->all) {
      my $bucket; my @roles = ('active', $person->roles);

      if ($person->joined <= $opts->{after}) {
         for my $role (map { $totals->{ $_ } //= 0; $_ } @roles) {
            $totals->{ $role }++;
         }
      }
      else {
         $bucket = $_get_bucket->( $df, $data, $lookup, $person->joined );
         $_inc_bucket->( $bucket, $person, 0 );
      }

      $person->resigned
         and $bucket = $_get_bucket->( $df, $data, $lookup, $person->resigned )
         and $_inc_bucket->( $bucket, $person, 1 );
   }

   for my $bucket (@{ $data }) {
      for my $role (@ROLES) {
         $totals->{ $role } //= 0;

         if (defined (my $count = $bucket->{ $role })) {
            $count->[ 2 ] = $totals->{ $role } + $count->[ 0 ] - $count->[ 1 ];
            $totals->{ $role } = $count->[ 2 ];
         }
         else { $bucket->{ $role } = [ 0, 0, $totals->{ $role } ] }
      }
   }

   return $data;
};

my $_deliveries_by_customer = sub {
   my ($self, $opts) = @_; my $data = { _deliveries => [] };

   my $rs = $self->schema->resultset( 'Journey' );

   $opts = $_exclusive_date_range->( $opts );
   $opts->{done} = TRUE; $opts->{order_by} = 'requested';

   for my $journey ($rs->search_for_journeys( $opts )->all) {
      push @{ $data->{_deliveries} }, $journey;

      my $customer = $journey->customer;
      my $rec = $data->{ $customer->id } //= { customer => $customer };
      my $index = 0;

      $journey->priority eq 'urgent' and $index = 1;
      $journey->priority eq 'emergency' and $index = 2;
      $rec->{count}->[ $index ] //= 0; $rec->{count}->[ $index ]++;
   }

   return $data;
};

my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

my $_get_expected = sub {
   my ($self, $basis) = @_;

   my $limits = $self->config->slot_limits;
   my $day_max = sum map { $limits->[ slot_limit_index 'day', $_ ] }
                         'controller', 'rider', 'driver';
   my $night_max = sum map { $limits->[ slot_limit_index 'night', $_ ] }
                           'controller', 'rider', 'driver';
   my $spw = (2 * $day_max) + (7 * $night_max);
   my $spm = (4 * $spw) + (5 * $spw / 14); # Not exact

   if    ($basis eq 'year')    { return sub { 12 * $spm } }
   elsif ($basis eq 'quarter') { return sub { 3 * $spm } }
   elsif ($basis eq 'month')   { return sub { $spm } }
   elsif ($basis eq 'week')    { return sub { $spw } }

   return sub { $_[ 0 ]->{date}->dow < 6 ? $night_max : $day_max + $night_max };
};

my $_get_period_options = sub {
   my ($self, $req, $pos, $opts) = @_; $pos //= 1; $opts //= {};

   my $now = now_dt;
   my $after = $req->uri_params->( $pos, { optional => TRUE } )
      // local_dt( $now )->truncate( to => 'year' )->ymd;
   my $before = $req->uri_params->( $pos + 1, { optional => TRUE } )
      // local_dt( $now )->subtract( days => 1 )->ymd;

   $opts->{after} = to_dt $after; $opts->{before} = to_dt $before;
   $opts->{period} = $req->query_params->( 'period', { optional => TRUE } );

   return $opts;
};

my $_get_role_name = sub {
   my ($self, $req, $pos, $opts) = @_; $pos //= 0; $opts //= {};

   my $role = $req->uri_params->( $pos, { optional => TRUE } ) // 'all';

   $opts->{role_name} = $role;

   return $opts;
};

my $_get_rota_name = sub {
   my ($self, $req, $pos, $opts) = @_; $pos //= 0; $opts //= {};

   my $rota_name = $req->uri_params->( $pos, { optional => TRUE } ) // 'main';

   $opts->{rota_name} = $rota_name;
   $opts->{rota_type} = $self->$_find_rota_type( $rota_name )->id;

   return $opts;
};

my $_people_meta_summary_table = sub {
   my ($self, $req, $form, $data, $opts) = @_;

   my $moniker = $self->moniker;
   my $basis = $_get_date_function->( $req, $opts )->();
   my $headers =
      [ { value => locm $req, 'people_meta_summary_heading_0' },
        map { $_people_meta_header_link->( $req, $moniker, $opts, $_ ) }
        1 .. 5 ];
   my $table = p_table $form, { headers => $headers };

   for my $bucket (@{ $data }) {
      my $row  = p_row $table;
      my $args = $_link_args->( $opts->{role_name}, $basis, $bucket->{date} );
      my $href = uri_for_action $req, "${moniker}/people_meta", $args;

      p_cell $row, { value => f_link $bucket->{key}, $href };

      for my $role (@ROLES) {
         p_cell $row, { class => 'align-right',
                        value => $bucket->{ $role }->[ 2 ] // 0 };
      }
   }

   return $table;
};

my $_slots_row = sub {
   my ($self, $req, $rota_name, $df, $basis, $rec, $max_count) = @_;

   my $counts = $rec->{count};
   my $args = $_link_args->( $rota_name, $basis, $rec->{date} );
   my $href = uri_for_action $req, $self->moniker.'/slots', $args;

   return [ { value => f_link $df->( $rec->{date} ), $href },
            map { { class => 'align-right', value => $counts->[ $_ ] // 0 } }
            0 .. $max_count ];
};

# Public methods
sub customers : Role(controller) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options( $req, 0 );
   my $href = uri_for_action $req, $actp, [ 'customers' ];
   my $form = blank_form 'date-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ], selected => 'customer_report',
                title => locm $req, 'customer_report_title' };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_deliveries_by_customer( $opts );
   my $headers = $_report_headers->( $req, 'customers', 4 );
   my $table = $page->{content} = p_table $form, { headers => $headers };

   p_row $table, [ map   { $_report_row->( $_->{customer}->name, $_, 3 ) }
                   map   { $data->{ $_ } }
                   map   { $_sum_counts->( $data, $_, 3 ) }
                   grep  { not m{ \A _ }mx }
                   keys %{ $data } ];

   p_list $form, NUL, $_dl_links->( $req, 'customers', $opts ), $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub date_control_action : Role(person_manager) Role(rota_manager) {
   my ($self, $req) = @_;

   my $report = $req->uri_params->( 0 );
   my $arg1 = $req->uri_params->( 1, { optional => TRUE } );
   my $args = []; $arg1 and push @{ $args }, $arg1;
   my $after = $req->body_params->( 'after_date' );
   my $before = $req->body_params->( 'before_date' );
   my $prev_after = $req->body_params->( 'prev_after_date' );
   my $prev_before = $req->body_params->( 'prev_before_date' );
   my $period = $req->body_params->( 'display_period', { optional => TRUE } );
   my $params = {};

   if ($period and $after eq $prev_after and $before eq $prev_before) {
      ($after, $before) = $_expand_range->( $period );
      $params->{period} = $period;
   }

   push @{ $args }, local_dt( to_dt $after )->ymd;
   push @{ $args }, local_dt( to_dt $before )->ymd;

   my $actionp = $self->moniker."/${report}";
   my $location = uri_for_action $req, $actionp, $args, $params;

   return { redirect => { location => $location } };
}

sub deliveries : Role(controller) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options( $req, 0 );
   my $href = uri_for_action $req, $actp, [ 'deliveries' ];
   my $form = blank_form 'date-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ],
                selected => 'delivery_report',
                title => locm $req, 'delivery_report_title' };

   $_push_date_controls->( $page, $opts );

   my $outer_table = p_table $form, {};
   my $full_table = $page->{content} = p_table {}, {
      headers => $_delivery_headers->( $req ) };
   my $sample_table = p_table {}, {
      class => 'embeded', headers => $_delivery_headers->( $req ) };
   my $container = p_container {}, $sample_table, { class => 'wide-content' };
   my $data = $self->$_deliveries_by_customer( $opts )->{_deliveries};
   my @rows = map { $_delivery_row->( $req, $_ ) } @{ $data };

   p_row $outer_table,  [ { class => 'embeded', value => $container } ];
   p_row $sample_table, [ @rows[ 0 .. 10 ] ];
   p_row $full_table,   [ @rows ];

   p_list $form, NUL, $_dl_links->( $req, 'deliveries', $opts ),
          $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub people : Role(person_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options
      ( $req, 1, $self->$_get_rota_name( $req ) );
   my $href = uri_for_action $req, $actp, [ 'people', $opts->{rota_name} ];
   my $form = blank_form 'date-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ], selected => 'people_report',
                title => locm $req, 'people_report_title' };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_counts_by_person( $opts );
   my $headers = $_report_headers->( $req, 'people', 5 );
   my $table = $page->{content} = p_table $form, { headers => $headers };

   p_row $table, [ map   { $_report_row->( $_->{person}->label, $_, 4 ) }
                   map   { $data->{ $_ } }
                   sort  { $_compare_counts->( $data, $a, $b, 4 ) }
                   map   { $_sum_counts->( $data, $_, 4 ) }
                   keys %{ $data } ];

   p_list $form, NUL, $_dl_links->( $req, 'people', $opts ), $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub people_meta : Role(person_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options
      ( $req, 1, $self->$_get_role_name( $req ) );
   my $name = $opts->{role_name};
   my $href = uri_for_action $req, $actp, [ 'people_meta', $name ];
   my $form = blank_form 'date-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ], selected => 'people_meta_report',
                title => $_people_meta_report_title->( $req, $name ) };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_counts_of_people( $req, $opts );

   if ($name ne 'all') {
      $page->{content} = $_people_meta_table->( $req, $form, $data, $name );
   }
   else {
      $page->{content} = $self->$_people_meta_summary_table
         ( $req, $form, $data, $opts );
   }

   p_list $form, NUL, $_dl_links->( $req, 'people_meta', $opts ),
      $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub slots : Role(rota_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options
      ( $req, 1, $self->$_get_rota_name( $req ) );
   my $name = $opts->{rota_name};
   my $href = uri_for_action $req, $actp, [ 'slots', $name ];
   my $form = blank_form 'date-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ], selected => 'slot_report',
                title => locm $req, 'slot_report_title' };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_counts_by_slot( $req, $opts );
   my $df = $_get_date_function->( $req, $opts );
   my $basis = $df->();
   my $expected = $self->$_get_expected( $basis );
   my $headers = $_report_headers->( $req, 'slot', 4 );
   my $table = $page->{content} = p_table $form, { headers => $headers };

   p_row $table, [ map { $self->$_slots_row( $req, $name, $df, $basis, $_, 3 ) }
                   map { $_slot_utilisation->( $_, $expected ) }
                      @{ $data } ];

   p_list $form, NUL, $_dl_links->( $req, 'slots', $opts ), $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(rota_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options
      ( $req, 1, $self->$_get_rota_name( $req ) );
   my $href = uri_for_action $req, $actp, [ 'vehicles', $opts->{rota_name} ];
   my $form = blank_form 'date-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ], selected => 'vehicle_report',
                title => locm $req, 'vehicle_report_title' };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_counts_by_vehicle( $opts );
   my $headers = $_report_headers->( $req, 'vehicle', 4 );
   my $table = $page->{content} = p_table $form, { headers => $headers };

   p_row $table, [ map   { $_report_row->( $_->{vehicle}->label, $_, 3 ) }
                   map   { $data->{ $_ } }
                   sort  { $_compare_counts->( $data, $a, $b, 3 ) }
                   map   { $_sum_counts->( $data, $_, 3 ) }
                   keys %{ $data } ];

   p_list $form, NUL, $_dl_links->( $req, 'vehicles', $opts ), $_link_opts->();

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Report - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Report;
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
