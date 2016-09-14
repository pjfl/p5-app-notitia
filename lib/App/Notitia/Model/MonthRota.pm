package App::Notitia::Model::MonthRota;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SHIFT_TYPE_ENUM SPC TRUE );
use App::Notitia::Form      qw( blank_form p_tag );
use App::Notitia::Util      qw( display_duration js_server_config
                                js_submit_config lcm_for locm
                                register_action_paths slot_limit_index
                                to_dt uri_for_action );
use Class::Usul::Functions  qw( sum );
use Class::Usul::Time       qw( time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'month';

register_action_paths
   'month/assign_summary' => 'assignment-summary',
   'month/month_rota' => 'month-rota';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );
   my $name  = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $page  = $stash->{page};

   $page->{location} = 'schedule';
   $stash->{navigation}
      = $self->rota_navigation_links( $req, $page, 'month', $name );

   return $stash;
};

# Private functions
my $_is_this_month = sub {
   my ($rno, $local_dt) = @_; $rno > 0 and return TRUE;

   return $local_dt->day < 15 ? TRUE : FALSE;
};

my $_local_dt = sub {
   return $_[ 0 ]->clone->set_time_zone( 'local' );
};

my $_onclick_relocate = sub {
   my ($page, $k, $href) = @_;

   push @{ $page->{literal_js} },
      js_submit_config $k, 'click', 'location', [ "${href}" ];

   return;
};

my $_month_label = sub {
   return { class => 'day-of-week',
            value => locm $_[ 0 ], 'month_rota_heading_'.$_[ 1 ] };
};

my $_month_rota_headers = sub {
   return [ map {  $_month_label->( $_[ 0 ], $_ ) } 0 .. 7 ];
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
   my ($req, $rota_name, $date) = @_; my $local_dt = $_local_dt->( $date );

   $date = $local_dt->month_name.SPC.$local_dt->year;

   return locm $req, 'month_rota_title', locm( $req, $rota_name ), $date;
};

my $_next_month = sub {
   my ($req, $actionp, $rota_name, $date) = @_;

   $date = $_local_dt->( $date )->truncate( to => 'day' )
                                  ->set( day => 1 )->add( months => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_prev_month = sub {
   my ($req, $actionp, $rota_name, $date) = @_;

   $date = $_local_dt->( $date )->truncate( to => 'day' )
                                  ->set( day => 1 )->subtract( months => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_summary_link_value = sub {
   my $opts = shift; my $class = 'vehicle-not-needed'; my $value = NUL;

   if    ($opts->{vehicle    }) { $value = 'V'; $class = 'vehicle-assigned'  }
   elsif ($opts->{vehicle_req}) { $value = 'R'; $class = 'vehicle-requested' }

   return $class, $value;
};

my $_summary_link = sub {
   my ($req, $type, $span, $id, $opts) = @_;

   $opts or return { colspan => $span, value => '&nbsp;' x 2 };

   my ($class, $value) = $_summary_link_value->( $opts );

   $class .= ' server tips';
   not $value and $opts->{operator}->id and $value = 'C';

   my $title = locm $req, (ucfirst $type).' Assignment';
   my $style = NUL; $opts->{vehicle} and $opts->{vehicle}->colour
      and $style = 'background-color: '.$opts->{vehicle}->colour.';';

   return { class => $class, colspan => $span,  name  => $id,
            style => $style, title   => $title, value => $value };
};

my $_week_number = sub {
   my ($date, $rno) = @_;

   my $week = $_local_dt->( $date )->add( days => 7 * $rno );

   return { class => 'month-rota-week-number', value => $week->week_number };
};

# Private methods
my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

my $_first_day_of_table = sub {
   my ($self, $req, $date) = @_;

   $date = $_local_dt->( $date )->set( day => 1 );

   $self->update_navigation_date( $req, $date );

   while ($date->day_of_week > 1) { $date = $date->subtract( days => 1 ) }

   return $date->set_time_zone( 'GMT' );
};

my $_month_table = sub {
   my ($self, $req, $rota_name) = @_;

   my $max_slots = $_month_rota_max_slots->( $self->config->slot_limits );

   return { caption   => locm( $req, 'month_rota_table_caption' ),
            headers   => $_month_rota_headers->( $req ),
            lcm       => lcm_for( 4, @{ $max_slots } ),
            max_slots => $max_slots,
            name      => $rota_name,
            rows      => [] };
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

            $slot and push @{ $page->{literal_js} }, js_server_config
               $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
         }
      }
   }

   return $cells;
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

my $_month_rota_page = sub {
   my ($self, $req, $rota_name, $rota_dt) = @_;

   my $actionp = $self->moniker.'/month_rota';

   return  {
      fields   => { nav => {
         next  => $_next_month->( $req, $actionp, $rota_name, $rota_dt ),
         prev  => $_prev_month->( $req, $actionp, $rota_name, $rota_dt ) }, },
      rota     => $self->$_month_table( $req, $rota_name ),
      template => [ '/menu', 'custom/month-table' ],
      title    => $_month_rota_title->( $req, $rota_name, $rota_dt ), };
};

my $_rota_summary_date_style = sub {
   my ($self, $local_dt, $data) = @_;

   my $limits = $self->config->slot_limits;
   my $day_max = sum( map { $limits->[ slot_limit_index 'day', $_ ] }
                      'controller', 'rider', 'driver' );
   my $night_max = sum( map { $limits->[ slot_limit_index 'night', $_ ] }
                        'controller', 'rider', 'driver' );
   my $wd = $night_max;
   my $we = $day_max + $night_max;
   my $ymd = $local_dt->ymd;
   my $slots_claimed = grep { $_ =~ m{ \A $ymd _ }mx } keys %{ $data };
   my $wanted = (0, $wd, $wd, $wd, $wd, $wd, $we, $we)[ $local_dt->day_of_week];
   my $colour = 'red';

   $slots_claimed > 0 and $colour = 'yellow';
   $slots_claimed == $wanted and $colour = 'green';

   return "background-color: ${colour}; color: black;"
};

my $_rota_summary = sub {
   my ($self, $req, $page, $local_dt, $has_event, $data) = @_;

   my $lcm   = $page->{rota}->{lcm};
   my $name  = $page->{rota}->{name};
   my $table = { class => 'month-rota', rows => [], type => 'table' };

   my $class = NUL; my $label = NUL; my $value = NUL;

   if (my $event = $has_event->{ $local_dt->ymd }) {
      my $opts = $_vreqs_for_event->( $self->schema, $event );

      $opts and ($class, $value) = $_summary_link_value->( $opts );
      $label = locm $req, 'Events';
   }

   push @{ $table->{rows} },
      [ { colspan => $lcm / 4,
          style   => $self->$_rota_summary_date_style( $local_dt, $data ),
          value   => $local_dt->day },
        { colspan =>     $lcm / 4, value => $value, class => $class },
        { colspan => 2 * $lcm / 4, value => $label } ];

   push @{ $table->{rows} }, $self->$_summary_cells
      ( $req, $page, $local_dt, [ 'day', 'night' ], [ 'controller' ], $data, 0);

   push @{ $table->{rows} }, $self->$_summary_cells
      ( $req, $page, $local_dt, [ 'day' ], [ 'rider', 'driver' ], $data, 1 );

   push @{ $table->{rows} }, $self->$_summary_cells
      ( $req, $page, $local_dt, [ 'night' ], [ 'rider', 'driver' ], $data, 2 );

   my $href = uri_for_action $req, 'day/day_rota', [ $name, $local_dt->ymd ];
   my $id   = "${name}_".$local_dt->ymd;

   $_onclick_relocate->( $page, $id, $href );

   return { class => 'month-rota submit', name => $id, value => $table };
};

my $_slot_assignments = sub {
   my ($self, $opts) = @_; $opts = { %{ $opts } }; delete $opts->{event_type};

   my $slot_rs = $self->schema->resultset( 'Slot' ); my $data = {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $k = $_local_dt->( $slot->start_date )->ymd.'_'.$slot->key;

      $data->{ $k } = { name        => $slot->key,
                        operator    => $slot->operator,
                        slot        => $slot,
                        vehicle     => $slot->vehicle,
                        vehicle_req => $slot->bike_requested };
   }

   return $data;
};

# Public methods
sub assign_summary : Role(any) {
   my ($self, $req) = @_;

   my ($rota_name, $rota_date, $shift_type, $slot_type, $subslot)
                =  split m{ _ }mx, $req->uri_params->( 0 ), 5;
   my $key      =  "${shift_type}_${slot_type}_${subslot}";
   my $rota_dt  =  to_dt $rota_date;
   my $stash    =  $self->dialog_stash( $req );
   my $form     =  $stash->{page}->{forms}->[ 0 ] = blank_form;
   my $data     =  $self->$_slot_assignments( {
      rota_type => $self->$_find_rota_type( $rota_name )->id,
      on        => $rota_dt } )->{ $_local_dt->( $rota_dt )->ymd."_${key}" };
   my $operator =  $data->{operator};
   my $who      =  $operator->label;
   my $opts     =  { class => 'label-column' };
   my ($start, $end) = display_duration $req, $data->{slot};

   $operator->postcode and $who .= ' ('.$operator->outer_postcode.')';

   p_tag $form, 'p', $who, $opts;

   $operator->mobile_phone and
       p_tag $form, 'p', "\x{260E} ".$operator->mobile_phone, $opts;

   $data->{vehicle} and p_tag $form, 'p', $data->{vehicle}->label, $opts;

   p_tag $form, 'p', $start, $opts; p_tag $form, 'p', $end, $opts;

   return $stash;
}

sub month_rota : Role(any) {
   my ($self, $req) = @_;

   my $params    =  $req->uri_params;
   my $rota_name =  $params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date =  $params->( 1, { optional => TRUE } ) // time2str '%Y-%m-01';
   my $rota_dt   =  to_dt $rota_date;
   my $page      =  $self->$_month_rota_page( $req, $rota_name, $rota_dt );
   my $opts      =  {
      after      => $rota_dt->clone->subtract( days => 1 ),
      before     => $rota_dt->clone->add( days => 31 ),
      rota_type  => $self->$_find_rota_type( $rota_name )->id };
   my $events    =  $self->schema->resultset( 'Event' )->has_events_for( $opts);
   my $assigned  =  $self->$_slot_assignments( $opts );
   my $first     =  $self->$_first_day_of_table( $req, $rota_dt );

   for my $rno (0 .. 5) {
      my $row = [];
      my $dayno = $_local_dt->( $first )->add( days => 7 * $rno )->day;

      $rno > 3 and $dayno == 1 and last;
      push @{ $row }, $_week_number->( $first, $rno );

      for my $offset (map { 7 * $rno + $_ } 0 .. 6) {
         my $cell = { class => 'month-rota', value => NUL };
         my $ldt  = $_local_dt->( $first )->add( days => $offset );

         $dayno = $ldt->day; $rno > 3 and $dayno == 1 and last;
         $_is_this_month->( $rno, $ldt ) and $cell = $self->$_rota_summary
            ( $req, $page, $ldt, $events, $assigned );
         push @{ $row }, $cell;
      }

      $row->[ 0 ] and push @{ $page->{rota}->{rows} }, $row;
      $rno > 3 and $dayno == 1 and last;
   }

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::MonthRota - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::MonthRota;
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
