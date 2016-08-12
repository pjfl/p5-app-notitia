package App::Notitia::Model::Report;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_cell p_date p_row p_table );
use App::Notitia::Util      qw( js_submit_config locm now_dt to_dt
                                register_action_paths slot_limit_index
                                uri_for_action );
use Class::Usul::Functions  qw( sum throw );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'report';

register_action_paths
   'report/controls' => 'report-controls',
   'report/people_meta' => 'people-meta-report',
   'report/people' => 'people-report',
   'report/slots' => 'slots-report',
   'report/vehicles' => 'vehicles-report';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

my @ROLES = qw( active rider controller driver fund_raiser );

# Private functions
my $_local_dt = sub {
   return $_[ 0 ]->clone->set_time_zone( 'local' );
};

my $_compare_counts = sub {
   my ($data, $k1, $k2, $index) = @_;

   return $data->{ $k2 }->{count}->[ $index ]
      <=> $data->{ $k1 }->{count}->[ $index ];
};

my $_exclusive_date_range = sub {
   my $opts = shift; $opts = { %{ $opts } };

   $opts->{after} = $opts->{after}->clone->subtract( days => 1 );
   $opts->{before} = $opts->{before}->clone->add( days => 1 );
   return $opts;
};

my $_find_insertion_pos = sub {
   my ($data, $dt) = @_; my $i = 0;

   $i++ while (defined $data->[ $i ] and $data->[ $i ]->{date} < $dt);

   return $i;
};

my $_get_bucket = sub {
   my ($df, $data, $lookup, $dt) = @_;

   my $key = $df->( $_local_dt->( $dt ) );

   exists $lookup->{ $key } and return $lookup->{ $key };

   my $bucket = $lookup->{ $key } = { date => $dt, key => $key };

   splice @{ $data }, $_find_insertion_pos->( $data, $dt ), 0, $bucket;

   return $bucket;
};

my $_get_date_function = sub {
   my $opts = shift;
   my $after = $opts->{after};
   my $before = $opts->{before};
   my $drtn = $_local_dt->( $after )->delta_md( $_local_dt->( $before ) );

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
   elsif ($drtn->months > 2
          or ($drtn->months == 2 and ($drtn->weeks > 0 or $drtn->days > 0))) {
      return sub {
         my $dt = shift; $dt or return 'week';

         $dt = $dt->clone->truncate( to => 'week' );

         return 'Wk'.$dt->week_number.SPC.$dt->dmy( '/' );
      };
   }

   return sub { $_[ 0 ] ? $_[ 0 ]->dmy( '/' ) : 'day' };
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

my $_onchange_submit = sub {
   my ($page, $k) = @_;

   push @{ $page->{literal_js} },
      js_submit_config $k, 'change', 'submitForm',
                       [ 'display_control', 'display-control' ];

   return;
};

my $_push_date_controls = sub {
   my ($page, $opts) = @_; my $form = $page->{forms}->[ 0 ];

   p_date $form, 'after_date', $opts->{after}, {
      class => 'date-field submit' };
   p_date $form, 'before_date', $opts->{before}, {
      class => 'date-field submit', label_class => 'right' };

   $_onchange_submit->( $page, 'after_date' );
   $_onchange_submit->( $page, 'before_date' );

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
   my $from = $_local_dt->( $opts->{after} )->ymd;
   my $to   = $_local_dt->( $opts->{before} )->ymd;
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
   return;
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
   my ($self, $opts) = @_; my $df = $_get_date_function->( $opts );

   $opts = $_exclusive_date_range->( $opts ); delete $opts->{rota_name};

   my $slot_rs = $self->schema->resultset( 'Slot' );
   my $data = []; my $lookup = {}; $opts->{order_by} = 'rota.date';

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $key = $df->( my $date = $_local_dt->( $slot->date ) );
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
   my ($self, $opts) = @_; my $df = $_get_date_function->( $opts );

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
   my $report_from = $req->uri_params->( $pos, { optional => TRUE } )
      // $_local_dt->( $now )->subtract( months => 1 )->ymd;
   my $report_to = $req->uri_params->( $pos + 1, { optional => TRUE } )
      // $_local_dt->( $now )->subtract( days => 1 )->ymd;

   $opts->{after} = to_dt( $report_from );
   $opts->{before} = to_dt( $report_to );

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

my $_people_meta_link_args = sub {
   my ($opts, $dt) = @_;

   my $name = $opts->{role_name};
   my $basis = $_get_date_function->( $opts )->();
   my $from = $_local_dt->( $dt );
   my $to =  $_local_dt->( $dt );

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

my $_people_meta_summary_table = sub {
   my ($self, $req, $form, $data, $opts) = @_;

   my $moniker = $self->moniker;
   my $headers =
      [ { value => locm $req, 'people_meta_summary_heading_0' },
        map { $_people_meta_header_link->( $req, $moniker, $opts, $_ ) }
        1 .. 5 ];
   my $table = p_table $form, { headers => $headers };

   for my $bucket (@{ $data }) {
      my $row  = p_row $table;
      my $args = $_people_meta_link_args->( $opts, $bucket->{date} );
      my $href = uri_for_action $req, "${moniker}/people_meta", $args;

      p_cell $row, { value => f_link $bucket->{key}, $href };

      for my $role (@ROLES) {
         p_cell $row, { class => 'align-right',
                        value => $bucket->{ $role }->[ 2 ] // 0 };
      }
   }

   return;
};

# Public methods
sub controls : Role(person_manager) Role(rota_manager) {
   my ($self, $req) = @_;

   my $report = $req->uri_params->( 0 );
   my $args = [ $req->uri_params->( 1 ) ];
   my $after = $_local_dt->( to_dt $req->body_params->( 'after_date' ) );
   my $before = $_local_dt->( to_dt $req->body_params->( 'before_date' ) );

   push @{ $args }, $after->ymd, $before->ymd;

   my $location = uri_for_action $req, $self->moniker."/${report}", $args;
   my $message  = [ $req->session->collect_status_message( $req ) ];

   return { redirect => { location => $location, message => $message } };
}

sub people : Role(person_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options
      ( $req, 1, $self->$_get_rota_name( $req ) );
   my $href = uri_for_action $req, $actp, [ 'people', $opts->{rota_name} ];
   my $form = blank_form 'display-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ],
                selected => 'people_report',
                title => locm $req, 'people_report_title' };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_counts_by_person( $opts );
   my $headers = $_report_headers->( $req, 'people', 5 );
   my $table = p_table $form, { headers => $headers };

   p_row $table, [ map   { $_report_row->( $_->{person}->label, $_, 4 ) }
                   map   { $data->{ $_ } }
                   sort  { $_compare_counts->( $data, $a, $b, 4 ) }
                   map   { $_sum_counts->( $data, $_, 4 ) }
                   keys %{ $data } ];

   return $self->get_stash( $req, $page );
}

sub people_meta : Role(person_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options
      ( $req, 1, $self->$_get_role_name( $req ) );
   my $name = $opts->{role_name};
   my $href = uri_for_action $req, $actp, [ 'people_meta', $name ];
   my $form = blank_form 'display-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ],
                selected => 'people_meta_report',
                title => $_people_meta_report_title->( $req, $name ) };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_counts_of_people( $opts );

   if ($name ne 'all') { $_people_meta_table->( $req, $form, $data, $name ) }
   else { $self->$_people_meta_summary_table( $req, $form, $data, $opts ) }

   return $self->get_stash( $req, $page );
}

sub slots : Role(rota_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options
      ( $req, 1, $self->$_get_rota_name( $req ) );
   my $href = uri_for_action $req, $actp, [ 'slots', $opts->{rota_name} ];
   my $form = blank_form 'display-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ],
                selected => 'slots_report',
                title => locm $req, 'slots_report_title' };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_counts_by_slot( $opts );
   my $df = $_get_date_function->( $opts );
   my $expected = $self->$_get_expected( $df->() );
   my $headers = $_report_headers->( $req, 'slot', 4 );
   my $table = p_table $form, { headers => $headers };

   p_row $table, [ map { $_report_row->( $df->( $_->{date} ), $_, 3 ) }
                   map { $_slot_utilisation->( $_, $expected ) }
                      @{ $data } ];

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(rota_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options
      ( $req, 1, $self->$_get_rota_name( $req ) );
   my $href = uri_for_action $req, $actp, [ 'vehicles', $opts->{rota_name} ];
   my $form = blank_form 'display-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ],
                selected => 'vehicles_report',
                title => locm $req, 'vehicles_report_title' };

   $_push_date_controls->( $page, $opts );

   my $data = $self->$_counts_by_vehicle( $opts );
   my $headers = $_report_headers->( $req, 'vehicle', 4 );
   my $table = p_table $form, { headers => $headers };

   p_row $table, [ map   { $_report_row->( $_->{vehicle}->label, $_, 3 ) }
                   map   { $data->{ $_ } }
                   sort  { $_compare_counts->( $data, $a, $b, 3 ) }
                   map   { $_sum_counts->( $data, $_, 3 ) }
                   keys %{ $data } ];

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
