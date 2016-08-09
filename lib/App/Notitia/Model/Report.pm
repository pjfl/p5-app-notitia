package App::Notitia::Model::Report;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form p_date p_row p_table );
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

# Private functions
my $_compare_counts = sub {
   my ($data, $k1, $k2, $index) = @_;

   return $data->{ $k2 }->{count}->[ $index ]
      <=> $data->{ $k1 }->{count}->[ $index ];
};

my $_get_date_function = sub {
   my $opts = shift; my $duration = $opts->{before}->delta_md( $opts->{after} );

   if ($duration->years > 2 or ($duration->years == 2
       and ($duration->months > 0 or $duration->days > 0))) {
      return sub { $_[ 0 ]->year }, 'year';
   }
   elsif ($duration->years == 2 or ($duration->years == 1
          and ($duration->months > 0 or $duration->days > 0))) {
      return sub { 'Q'.$_[ 0 ]->quarter.SPC.$_[ 0 ]->year }, 'quarter';
   }
   elsif ($duration->years == 1 or $duration->months > 3) {
      return sub { $_[ 0 ]->month_name.SPC.$_[ 0 ]->year }, 'month';
   }
   elsif ($duration->months > 1 or ($duration->months == 1
          and $duration->days > 1)) {
      return sub {
         my $dt = (shift)->clone->truncate( to => 'week' );

         return 'Wk'.$dt->week_number.SPC.$dt->dmy( '/' );
      }, 'week';
   }

   return sub { $_[ 0 ]->dmy( '/' ) }, 'day';
};

my $_get_expected = sub {
   my ($day_max, $night_max, $basis) = @_;

   my $spw = (2 * $day_max) + (7 * $night_max);
   my $spm = (4 * $spw) + (5 * $spw / 14); # Not exact

   if    ($basis eq 'year')    { return sub { 12 * $spm } }
   elsif ($basis eq 'quarter') { return sub { 3 * $spm } }
   elsif ($basis eq 'month')   { return sub { $spm } }
   elsif ($basis eq 'week')    { return sub { $spw } }

   return sub { $_[ 0 ]->{date}->dow < 6 ? $night_max : $day_max + $night_max };
};

my $_increment_resource_count = sub {
   my ($slot, $rec) = @_; my $index;

   $slot->type_name->is_controller and $index = 0;
   $slot->type_name->is_rider and $index = 1;
   $slot->type_name->is_driver and $index = 2;
   defined $index or return;
   $rec->{count}->[ $index ] //= 0; $rec->{count}->[ $index ]++;
   return;
};

my $_local_dt = sub {
   return $_[ 0 ]->clone->set_time_zone( 'local' );
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

my $_report_row = sub {
   my ($label, $rec, $max_count) = @_; my $counts = $rec->{count};

   return [ { value => $label },
            map { { class => 'align-right', value => $counts->[ $_ ] // 0 } }
            0 .. $max_count ];
};

my $_report_headers = sub {
   my ($req, $type, $max_count) = @_;

   return [ map { { value => locm $req, "${type}_report_heading_${_}" } }
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

# Private methods
my $_counts_by_person = sub {
   my ($self, $opts) = @_;

   my $slot_rs = $self->schema->resultset( 'Slot' );
   my $participent_rs = $self->schema->resultset( 'Participent' );
   my $attendees = $participent_rs->search_for_attendees( $opts );
   my $data = {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $person = $slot->operator;
      my $rec = $data->{ $person->shortcode } //= { person => $person };

      $_increment_resource_count->( $slot, $rec );
   }

   for my $person (map { $_->participent } $attendees->all) {
      my $rec = $data->{ $person->shortcode } //= { person => $person };

      $rec->{count}->[ 3 ] //= 0; $rec->{count}->[ 3 ]++;
   }

   return $data;
};

my $_counts_by_slot = sub {
   my ($self, $opts) = @_; $opts = { %{ $opts } };

   my ($function) = $_get_date_function->( $opts );
   my $slot_rs = $self->schema->resultset( 'Slot' );
   my $data = []; my $lookup = {}; $opts->{order_by} = 'rota.date';

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $key = $function->( my $date = $_local_dt->( $slot->date ) );
      my $rec = { date => $date };

      if (exists $lookup->{ $key }) { $rec = $lookup->{ $key } }
      else { $lookup->{ $key } = $rec; push @{ $data }, $rec }

      $rec->{ $date->ymd.'_'.$slot->key } = $slot;
   }

   for my $rec (@{ $data }) {
      for my $key (grep { $_ ne 'count' && $_ ne 'date' } keys %{ $rec }) {
         $_increment_resource_count->( $rec->{ $key }, $rec );
      }
   }

   return $data;
};

my $_counts_by_vehicle = sub {
   my ($self, $opts) = @_;

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

my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

my $_get_period_options = sub {
   my ($self, $req) = @_;

   my $now = now_dt;
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $report_from = $req->uri_params->( 1, { optional => TRUE } )
      // $_local_dt->( $now )->subtract( months => 1 )->ymd;
   my $report_to = $req->uri_params->( 2, { optional => TRUE } )
      // $_local_dt->( $now )->ymd;

   return { after => to_dt( $report_from )->subtract( days => 1 ),
            before => to_dt( $report_to ),
            rota_name => $rota_name,
            rota_type => $self->$_find_rota_type( $rota_name )->id, };
};

# Public methods
sub controls : Role(person_manager) Role(rota_manager) {
   my ($self, $req) = @_;

   my $report = $req->uri_params->( 0 );
   my $rota_name = $req->uri_params->( 1 );
   my $after = $_local_dt->( to_dt $req->body_params->( 'after_date' ) );
   my $before = $_local_dt->( to_dt $req->body_params->( 'before_date' ) );
   my $args = [ $rota_name, $after->ymd, $before->ymd ];
   my $location = uri_for_action $req, $self->moniker."/${report}", $args;
   my $message  = [ $req->session->collect_status_message( $req ) ];

   return { redirect => { location => $location, message => $message } };
}

sub people : Role(person_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options( $req );
   my $name = delete $opts->{rota_name};
   my $data = $self->$_counts_by_person( $opts );
   my $href = uri_for_action $req, $actp, [ 'people', $name ];
   my $form = blank_form 'display-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ],
                selected => 'people_report',
                title => locm $req, 'people_report_title' };

   $_push_date_controls->( $page, $opts );

   my $headers = $_report_headers->( $req, 'people', 5 );
   my $table = p_table $form, { headers => $headers };

   p_row $table, [ map   { $_report_row->( $_->{person}->label, $_, 4 ) }
                   map   { $data->{ $_ } }
                   sort  { $_compare_counts->( $data, $a, $b, 4 ) }
                   map   { $_sum_counts->( $data, $_, 4 ) }
                   keys %{ $data } ];

   return $self->get_stash( $req, $page );
}

sub slots : Role(rota_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options( $req );
   my $name = delete $opts->{rota_name};
   my $data = $self->$_counts_by_slot( $opts );
   my $href = uri_for_action $req, $actp, [ 'slots', $name ];
   my ($display, $basis) = $_get_date_function->( $opts );
   my $limits = $self->config->slot_limits;
   my $day_max = sum map { $limits->[ slot_limit_index 'day', $_ ] }
                         'controller', 'rider', 'driver';
   my $night_max = sum map { $limits->[ slot_limit_index 'night', $_ ] }
                           'controller', 'rider', 'driver';
   my $expected = $_get_expected->( $day_max, $night_max, $basis );
   my $form = blank_form 'display-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ],
                selected => 'slots_report',
                title => locm $req, 'slots_report_title' };

   $_push_date_controls->( $page, $opts );

   my $headers = $_report_headers->( $req, 'slot', 4 );
   my $table = p_table $form, { headers => $headers };

   p_row $table, [ map { $_report_row->( $display->( $_->{date} ), $_, 3 ) }
                   map { $_slot_utilisation->( $_, $expected ) }
                      @{ $data } ];

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(rota_manager) {
   my ($self, $req) = @_;

   my $actp = $self->moniker.'/controls';
   my $opts = $self->$_get_period_options( $req );
   my $name = delete $opts->{rota_name};
   my $data = $self->$_counts_by_vehicle( $opts );
   my $href = uri_for_action $req, $actp, [ 'vehicles', $name ];
   my $form = blank_form 'display-control', $href, { class => 'wide-form' };
   my $page = { forms => [ $form ],
                selected => 'vehicles_report',
                title => locm $req, 'vehicles_report_title' };

   $_push_date_controls->( $page, $opts );

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
