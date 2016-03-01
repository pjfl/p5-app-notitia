package App::Notitia::Model::Schedule;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE HASH_CHAR NUL
                                SHIFT_TYPE_ENUM SPC TILDE TRUE );
use App::Notitia::Util      qw( loc register_action_paths rota_navigation_links
                                set_element_focus slot_limit_index
                                uri_for_action );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Time       qw( str2date_time time2str );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'sched';

register_action_paths
   'sched/slot'     => 'slot',
   'sched/index'    => 'index',
   'sched/day_rota' => 'rota';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = rota_navigation_links $req, 'main'; # TODO: Naughty

   return $stash;
};

# Private class attributes
my $_rota_types_id = {};

# Private functions
my $_slot_claimed = sub {
   return exists $_[ 0 ]->{ $_[ 1 ] }
       && exists $_[ 0 ]->{ $_[ 1 ] }->{operator} ? TRUE : FALSE;
};

my $_slot_identifier = sub {
   my ($rota_name, $rota_date, $shift_type, $slot_type, $subslot) = @_;

   $rota_name =~ s{ _ }{ }gmx;

   return sprintf '%s rota on %s %s shift %s slot %s',
          ucfirst( $rota_name ), $rota_date, $shift_type, $slot_type, $subslot;
};

my $_slot_label = sub {
   return $_slot_claimed->( $_[ 1 ], $_[ 2 ] )
        ? $_[ 1 ]->{ $_[ 2 ] }->{operator}->label : loc( $_[ 0 ], 'Vacant' );
};

my $_confirm_slot_button = sub {
   my ($req, $slot_type, $action) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, "confirm_${action}_tip", [ $slot_type ] );

   # Have left tip off as too noisey
   return { class => 'right', label => 'confirm', value => "${action}_slot" };
};

my $_dialog = sub {
   my ($req, $k, $href, $name, $title) = @_; $title = loc( $req, $title );

   return "   behaviour.config.anchors[ '${k}' ] = {",
          "      method    : 'modalDialog',",
          "      args      : [ '${href}', {",
          "         name   : '${name}',",
          "         title  : '${title}',",
          "         useIcon: true } ] };";
};

my $_dialog_link = sub {
   my ($req, $slot_rows, $k, $slot_type) = @_;

   my $claimed = $_slot_claimed->( $slot_rows, $k );
   my $tip     = loc( $req, ($claimed ? 'yield_slot_tip' : 'claim_slot_tip'),
                      $slot_type );

   return { class => 'table-link windows',
            hint  => loc( $req, 'Hint' ),
            href  => HASH_CHAR,
            name  => $k,
            tip   => $tip,
            type  => 'link',
            value => $_slot_label->( $req, $slot_rows, $k ), };
};

my $_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "rota_heading_${_}" ) } } 0 .. 4 ];
};

my $_events = sub {
   my ($req, $page, $rota_dt, $todays_events) = @_;

   my $rota   = $page->{rota};
   my $events = $rota->{events};
   my $date   = $rota_dt->day_abbr.SPC.$rota_dt->day;

   push @{ $events }, [ { value   => $date, class => 'rota-date' },
                        { value   => ucfirst( $todays_events->next // NUL ),
                          colspan => 4 } ];

   while (defined (my $event = $todays_events->next)) {
      push @{ $events }, [ { value => undef },
                           { value => ucfirst( $event ), colspan => 4 } ];
   }

   return;
};

my $_push_driver_row = sub {
   my ($drivers, $req, $slot_rows, $k) = @_;

   push @{ $drivers },
      [ { value => loc( $req, $k ), class => 'rota-header' },
        { value => undef },
        { value => $_dialog_link->( $req, $slot_rows, $k, 'driver' ) },
        { value => undef, class => 'narrow' },
        { value => $slot_rows->{ $k }->{ops_veh}, class => 'narrow' }, ];

   return;
};

my $_push_rider_row = sub {
   my ($riders, $req, $slot_rows, $k) = @_;

   push @{ $riders },
      [ { value => loc( $req, $k ), class => 'rota-header' },
        { value => $slot_rows->{ $k }->{vehicle }, class => 'narrow' },
        { value => $_dialog_link->( $req, $slot_rows, $k, 'rider' ) },
        { value => $slot_rows->{ $k }->{bike_req},
          class => 'centre narrow' },
        { value => $slot_rows->{ $k }->{ops_veh }, class => 'narrow' }, ];

   return;
};

my $_operators_vehicle = sub {
   my $slot    = shift;
   my $pv      = $slot->personal_vehicles->first;
   my $pv_type = $pv ? $pv->type : NUL;

   return $pv_type eq '4x4' ? $pv_type
        : $pv_type eq 'car' ? ucfirst( $pv_type ) : undef;
};

# Private methods
my $_add_js_dialog = sub {
   my ($self, $req, $page, $args, $slot_rows, $name, $title) = @_;

   my $js = $page->{literal_js} //= []; my $k = $args->[ 2 ];

   my $action = $_slot_claimed->( $slot_rows, $k ) ? 'yield' : 'claim';

   $name = "${action}-${name}"; $title = (ucfirst $action).SPC.$title;

   my $path = $self->moniker.'/slot';
   my $href = uri_for_action( $req, $path, $args, { action => $action } );

   push @{ $js }, $_dialog->( $req, $k, $href, $name, $title );

   return;
};

my $_controllers = sub {
   my ($self, $req, $page, $rota_name, $rota_date, $slot_rows, $limits) = @_;

   my $rota = $page->{rota}; my $controls = $rota->{controllers};

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $max_slots = $limits->[ slot_limit_index $shift_type, 'controller' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k    = "${shift_type}_controller_${subslot}";
         my $args = [ $rota_name, $rota_date, $k ];
         my $link = $_dialog_link->( $req, $slot_rows, $k, 'controller' );

         push @{ $controls },
            [ { class => 'rota-header', value   => loc( $req, $k ), },
              { class => 'centre',      colspan => 4, value => $link } ];

         $self->$_add_js_dialog( $req, $page, $args, $slot_rows,
                                 'controller-slot', 'Controller Slot' );
      }
   }

   return;
};

my $_find_rota_type_id_for = sub {
   exists $_rota_types_id->{ $_[ 1 ] } or $_rota_types_id->{ $_[ 1 ] }
      = $_[ 0 ]->schema->resultset( 'Type' )->search
         ( { name    => $_[ 1 ], type => 'rota' },
           { columns => [ 'id' ] } )->single->id;

   return $_rota_types_id->{ $_[ 1 ] };
};

my $_riders_n_drivers = sub {
   my ($self, $req, $page, $rota_name, $rota_date, $slot_rows, $limits) = @_;

   my $shift_no = 0;

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $shift     = $page->{rota}->{shifts}->[ $shift_no++ ] = {};
      my $riders    = $shift->{riders } = [];
      my $drivers   = $shift->{drivers} = [];
      my $max_slots = $limits->[ slot_limit_index $shift_type, 'rider' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k    = "${shift_type}_rider_${subslot}";
         my $args = [ $rota_name, $rota_date, $k ];

         $_push_rider_row->( $riders, $req, $slot_rows, $k );
         $self->$_add_js_dialog( $req, $page, $args, $slot_rows,
                                 'rider-slot', 'Rider Slot' );
      }

      $max_slots = $limits->[ slot_limit_index $shift_type, 'driver' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k    = "${shift_type}_driver_${subslot}";
         my $args = [ $rota_name, $rota_date, $k ];

         $_push_driver_row->( $drivers, $req, $slot_rows, $k );
         $self->$_add_js_dialog( $req, $page, $args, $slot_rows,
                                 'driver-slot', 'Driver Slot' );
      }
   }

   return;
};

my $_get_page = sub {
   my ($self, $req, $name, $date, $todays_events, $slot_rows, $limits) = @_;

   my $rota_dt =  str2date_time $date, 'GMT';
   my $title   =  ucfirst( loc( $req, $name ) ).SPC
               .  loc( $req, 'rota for' ).SPC.$rota_dt->month_name;
   my $page    =  {
      rota     => { controllers => [],
                    events      => [],
                    headers     => $_headers->( $req ),
                    shifts      => [], },
      template => [ 'contents', 'rota' ],
      title    => $title };

   $_events->( $req, $page, $rota_dt, $todays_events );
   $self->$_controllers( $req, $page, $name, $date, $slot_rows, $limits );
   $self->$_riders_n_drivers( $req, $page, $name, $date, $slot_rows, $limits );

   return $page;
};

# Public methods
sub claim_slot_action {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $name      = $params->( 2 );
   my $opts      = { optional => TRUE };
   my $bike      = $req->body_params->( 'request_bike', $opts ) // FALSE;
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $req->username );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   # Without tz will create rota records prev. day @ 23:00 during summer time
   $person->claim_slot( $rota_name, str2date_time( $rota_date, 'GMT' ),
                        $shift_type, $slot_type, $subslot, $bike );

   my $args     = [ $rota_name, $rota_date ];
   my $location = uri_for_action( $req, 'sched/day_rota', $args );
   my $label    = $_slot_identifier->( $rota_name, $rota_date,
                                       $shift_type, $slot_type, $subslot );
   my $message  = [ 'User [_1] claimed slot [_2]', $req->username, $label ];

   return { redirect => { location => $location, message => $message } };
}

sub day_rota {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $today     = time2str '%Y-%m-%d';
   my $name      = $params->( 0, { optional => TRUE } ) // 'main';
   my $date      = $params->( 1, { optional => TRUE } ) // $today;
   my $type_id   = $self->$_find_rota_type_id_for( $name );
   my $slot_rs   = $self->schema->resultset( 'Slot' );
   my $slots     = $slot_rs->search
      ( { 'rota.type_id' => $type_id, 'rota.date' => $date },
        { columns  => [ qw( bike_requested operator.name
                            type vehicle.name subslot ) ],
          join     => [ { 'shift' => 'rota' }, 'operator', 'vehicle', ],
          prefetch => [ { 'shift' => 'rota' }, 'operator', 'vehicle',
                        'personal_vehicles' ] } );
   my $event_rs  = $self->schema->resultset( 'Event' );
   my $events    = $event_rs->search
      ( { 'rota.type_id' => $type_id, 'rota.date' => $date },
        { columns  => [ 'name' ], join => [ 'rota' ] } );
   my $limits    = $self->config->slot_limits;
   my $rows      = {};

   for my $slot ($slots->all) {
      $rows->{ $slot->shift->type.'_'.$slot->type.'_'.$slot->subslot }
         = { vehicle  =>  $slot->vehicle,
             operator =>  $slot->operator,
             bike_req => ($slot->bike_requested ? 'Y' : 'N'),
             ops_veh  =>  $_operators_vehicle->( $slot ) };
   }

   my $page = $self->$_get_page( $req, $name, $date, $events, $rows, $limits );

   return $self->get_stash( $req, $page );
}

sub index {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout   => 'index',
      template => [ 'contents', 'splash' ],
      title    => loc( $req, 'main_index_title' ), } );
}

sub slot {
   my ($self, $req) = @_;

   my $params = $req->uri_params;
   my $name   = $params->( 2 );
   my $args   = [ $params->( 0 ), $params->( 1 ), $name ];
   my $action = $req->query_params->( 'action' );
   my $stash  = $self->dialog_stash( $req, "${action}-slot" );
   my $page   = $stash->{page};
   my $fields = $page->{fields};

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   $fields->{confirm  } = $_confirm_slot_button->( $req, $slot_type, $action );
   $fields->{slot_href} = uri_for_action( $req, $self->moniker.'/slot', $args );

   $action eq 'claim' and $slot_type eq 'rider'
      and $fields->{request_bike} = bind( 'request_bike', TRUE );

   return $stash;
}

sub yield_slot_action {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $slot_name = $params->( 2 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $req->username );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $slot_name, 3;

   $person->yield_slot( $rota_name, str2date_time( $rota_date ),
                        $shift_type, $slot_type, $subslot );

   my $args     = [ $rota_name, $rota_date ];
   my $location = uri_for_action( $req, 'sched/day_rota', $args );
   my $label    = $_slot_identifier->( $rota_name, $rota_date,
                                       $shift_type, $slot_type, $subslot );
   my $message  = [ 'User [_1] yielded slot [_2]', $req->username, $label ];

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
