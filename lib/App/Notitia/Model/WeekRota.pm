package App::Notitia::Model::WeekRota;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SPC TRUE );
use App::Notitia::Util      qw( js_server_config js_submit_config
                                locm register_action_paths
                                to_dt uri_for_action );
use Class::Usul::Time       qw( time2str );
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
   'week/week_rota' => 'week-rota';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );
   my $name  = $req->uri_params->( 0, { optional => TRUE } ) // 'main';

   $stash->{nav}->{list} = $self->rota_navigation_links( $req, 'month', $name );
   $stash->{page}->{location} = 'schedule';

   return $stash;
};

# Private functions
my $_async_event_tip = sub {
   my ($req, $page, $tport) = @_;

   my $uri  = $tport->event->uri;
   my $href = uri_for_action $req, 'event/event_info', [ $uri ];

   push @{ $page->{literal_js} }, js_server_config
      $uri, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_async_slot_tip = sub {
   my ($req, $page, $moniker, $id) = @_;

   my $name    = $page->{rota}->{name};
   my $actionp = 'month/assign_summary';
   my $href    = uri_for_action $req, $actionp, [ "${name}_${id}" ];

   push @{ $page->{literal_js} }, js_server_config
      $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_async_v_event_tip = sub {
   my ($req, $page, $event) = @_;

   my $href = uri_for_action $req, 'event/vehicle_info', [ $event->uri ];

   push @{ $page->{literal_js} }, js_server_config
      $event->uri, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
};

my $_async_vreq_tip = sub {
   my ($req, $page, $event) = @_;

   my $actionp = 'asset/request_info';
   my $href    = uri_for_action $req, $actionp, [ $event->uri ];
   my $id      = 'request-'.$event->uri;

   push @{ $page->{literal_js} }, js_server_config
      $id, 'mouseover', 'asyncTips', [ "${href}", 'tips-defn' ];
   return;
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

# Private methods
my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
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

my $_week_rota_assignments = sub {
   my ($self, $req, $page, $rota_dt, $tuple, $cache, $tports, $events) = @_;

   my $moniker   = $self->moniker;
   my $rota_name = $page->{rota}->{name};
   my $class     = 'narrow week-rota submit server tips';
   my $row       = [ { class => 'narrow', value => $tuple->[ 0 ] } ];

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
                $_async_slot_tip->( $req, $page, $moniker, $id ); [ $id, $_ ] }
         grep { $_->vehicle->name eq $tuple->[ 1 ]->name }
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
         map  { $_async_event_tip->( $req, $page, $_ );
                [ $_->event->uri, $_ ] }
         grep { $_->vehicle->vrn eq $tuple->[ 1 ]->vrn }
         grep { $_->event->start_date eq $date } @{ $tports };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => $_->[ 0 ],
                    title => locm( $req, 'Vechicle Event' ),
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
   my $class     = 'narrow week-rota submit server tips';
   my $row       = [ { class => 'narrow', value => 'Requests' } ];

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
                $_async_slot_tip->( $req, $page, $moniker, $id ); [ $id, $_ ] }
         grep { $_->bike_requested and not $_->vehicle }
         map  { push @{ $cache->[ $cno ] }, $_; $_ }
         grep { $_->date eq $date } @{ $slots };

      push @{ $table->{rows} },
         map  { [ { class => $class,
                    name  => 'request-'.$_->[ 0 ],
                    title => locm( $req, 'Vehicle Request' ),
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
      template    => [ 'menu', 'week-table' ],
      title       => $_week_rota_title->( $req, $rota_name, $rota_dt ), };
   my $opts       =  {
      after       => $rota_dt->clone->subtract( days => 1),
      before      => $rota_dt->clone->add( days => 7 ),
      rota_type   => $self->$_find_rota_type( $rota_name )->id };
   my $event_rs   =  $self->schema->resultset( 'Event' );
   my $slot_rs    =  $self->schema->resultset( 'Slot' );
   my $tport_rs   =  $self->schema->resultset( 'Transport' );
   my $vehicle_rs =  $self->schema->resultset( 'Vehicle' );
   my $vreq_rs    =  $self->schema->resultset( 'VehicleRequest' );
   my @slots      =  $slot_rs->search_for_slots( $opts )->all;
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
