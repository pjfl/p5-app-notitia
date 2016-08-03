package App::Notitia::Model::DayRota;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( C_DIALOG FALSE NUL SPC
                                SHIFT_TYPE_ENUM TILDE TRUE );
use App::Notitia::Form      qw( blank_form f_link p_button
                                p_checkbox p_select );
use App::Notitia::Util      qw( assign_link dialog_anchor js_submit_config
                                locm make_tip register_action_paths slot_claimed
                                slot_identifier slot_limit_index to_dt to_msg
                                uri_for_action );
use Class::Usul::Functions  qw( is_member );
use Class::Usul::Time       qw( time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'day';

register_action_paths
   'day/day_rota' => 'day-rota',
   'day/slot' => 'slot';

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

# Private class attributes
my $_max_rota_cols = 4;

# Private functions
my $_add_js_dialog = sub {
   my ($req, $page, $args, $action, $name, $title) = @_;

   $name = "${action}-${name}";
   $title = locm $req, (ucfirst $action).SPC.$title;

   my $path = $page->{moniker}.'/slot';
   my $href = uri_for_action $req, $path, $args, { action => $action };
   my $js   = $page->{literal_js} //= [];

   push @{ $js }, dialog_anchor( $args->[ 2 ], $href, {
      name => $name, title => $title, useIcon => \1 } );

   return;
};

my $_day_label = sub {
   my $v    = locm $_[ 0 ], 'day_rota_heading_'.$_[ 1 ];
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

my $_onchange_submit = sub {
   my $page = shift;

   push @{ $page->{literal_js} },
      js_submit_config 'rota_date', 'change', 'submitForm',
                       [ 'rota_redirect', 'day-rota' ];

   return;
};

my $_onclick_relocate = sub {
   my ($page, $k, $href) = @_;

   push @{ $page->{literal_js} },
      js_submit_config $k, 'click', 'location', [ "${href}" ];

   return;
};

my $_operators_vehicle = sub {
   my ($slot, $cache) = @_; $slot->operator->id or return NUL; my $label;

   exists $cache->{ $slot->operator->id }
      and return $cache->{ $slot->operator->id };

   for my $pv ($slot->operator_vehicles->all) {
      $label = $pv->type eq '4x4' ? $pv->type
             : $pv->type eq 'car' ? ucfirst( $pv->type ) : undef;

      $label and last;
   }

   return $cache->{ $slot->operator->id } = $label // NUL;
};

my $_participents_link = sub {
   my ($req, $page, $event) = @_; $event or return;

   my $href  = uri_for_action $req, 'event/participents', [ $event->uri ];
   my $tip   = locm $req, 'participents_view_link', $event->label;

   return { class   => 'narrow',
            colspan => 1,
            value   => { class => 'list-icon', hint => locm( $req, 'Hint' ),
                         href  => $href,       name => 'view-participents',
                         tip   => $tip,        type => 'link',
                         value => '&nbsp;', } };
};

my $_slot_contact_info = sub {
   my ($req, $slot) = @_; slot_claimed $slot or return NUL;

   for my $role ('controller', 'rota_manager') {
      is_member $role, $req->session->roles
         and return '('.$slot->{operator}->mobile_phone.')';
   }

   return NUL;
};

my $_slot_label = sub {
   return slot_claimed( $_[ 1 ] ) ? $_[ 1 ]->{operator}->label
                                  : locm $_[ 0 ], 'Vacant';
};

my $_slot_link = sub {
   my ($req, $page, $data, $k, $slot_type) = @_;

   my $action = slot_claimed $data->{ $k } ? 'yield' : 'claim';
   my $value = $_slot_label->( $req, $data->{ $k } );
   my $opts = { action => $action,
                args => [ $slot_type,
                          $_slot_contact_info->( $req, $data->{ $k } ) ],
                name => $k, request => $req, value => $value };

   return { colspan => 2, value => f_link 'slot', C_DIALOG, $opts };
};

my $_summary_link = sub {
   my $opts = shift; my $class = 'vehicle-not-needed'; my $value = NUL;

   $opts or return { class => $class, value => '&nbsp;' x 2 };

   if    ($opts->{vehicle    }) { $value = 'V'; $class = 'vehicle-assigned'  }
   elsif ($opts->{vehicle_req}) { $value = 'R'; $class = 'vehicle-requested' }

   return { class => $class, value => $value };
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

my $_vehicle_request_link = sub {
   my ($schema, $req, $page, $event) = @_; $event or return;

   my $vreqs   = $_vreqs_for_event->( $schema, $event );
   my $href    = uri_for_action $req, 'asset/request_vehicle', [ $event->uri ];
   my $link    = { class => 'align-center embeded small-slot tips' };
   my $tip     = locm $req, 'vehicle_request_tip', $event->label;
   my $hint    = locm $req, 'Event Assignment';
   my $summary = $_summary_link->( $vreqs );

   $link->{title} = $hint.SPC.TILDE.SPC.$tip;
   $link->{value} = { class => $summary->{class}.' rota-link',
                      href  => $href,
                      name  => 'view-vehicle-requests',
                      type  => 'link',
                      value => $summary->{value}, };

   return $link;
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
            [ { class => 'rota-header', value   => locm( $req, $k ), },
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

   return [ { value => locm( $req, $k ), class => 'rota-header' },
            { value => undef },
            $_slot_link->( $req, $page, $data, $k, 'driver' ),
            { value => $data->{ $k }->{ops_veh}, class => 'narrow' }, ];
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
   my $tip  = locm $req, 'Click to view the [_1] event', $event->label;

   return {
      colspan  => $_max_rota_cols - 2,
      value    => {
         class => 'table-link', hint => locm( $req, 'Hint' ),
         href  => $href,        name => $event->name,
         tip   => $tip,         type => 'link',
         value => $event->name, }, };
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

   $_onchange_submit->( $page );
   return;
};

my $_rider_row = sub {
   my ($req, $page, $args, $data) = @_; my $k = $args->[ 2 ];

   return [ { value => locm( $req, $k ), class => 'rota-header' },
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
my $_day_page = sub {
   my ($self, $req, $name, $rota_dt, $todays_events, $data) = @_;

   my $schema   =  $self->schema;
   my $limits   =  $self->config->slot_limits;
   my $local_dt =  $_local_dt->( $rota_dt );
   my $date     =  $local_dt->month_name.SPC.$local_dt->day.SPC.$local_dt->year;
   my $title    =  locm $req, 'day_rota_title', locm( $req, $name ), $date;
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
      template  => [ '/menu', 'custom/day-table' ],
      title     => $title };

   $_events->( $schema, $req, $page, $name, $local_dt, $todays_events );
   $_controllers->( $req, $page, $name, $local_dt, $data, $limits );
   $_riders_n_drivers->( $req, $page, $name, $local_dt, $data, $limits );

   return $page;
};

my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

# Public methods
sub claim_slot_action : Role(rota_manager) Role(rider) Role(controller)
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
   my $location = uri_for_action $req, $self->moniker.'/day_rota', $args;
   my $label    = slot_identifier
                     $rota_name, $rota_date, $shift_type, $slot_type, $subslot;
   my $message  = [ to_msg '[_1] claimed slot [_2]', $person->label, $label ];

   return { redirect => { location => $location, message => $message } };
}

sub day_rota : Role(any) {
   my ($self, $req) = @_; my $vehicle_cache = {};

   my $params    = $req->uri_params;
   my $today     = time2str '%Y-%m-%d';
   my $name      = $params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $params->( 1, { optional => TRUE } ) // $today;
   my $rota_dt   = to_dt $rota_date;
   my $type_id   = $self->$_find_rota_type( $name )->id;
   my $slot_rs   = $self->schema->resultset( 'Slot' );;
   my $event_rs  = $self->schema->resultset( 'Event' );
   my $events    = $event_rs->search_for_a_days_events( $type_id, $rota_dt );
   my $opts      = { rota_type => $type_id, on => $rota_dt };
   my $slot_data = {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      $slot_data->{ $slot->key } =
         { name        => $slot->key,
           operator    => $slot->operator,
           ops_veh     => $_operators_vehicle->( $slot, $vehicle_cache ),
           vehicle     => $slot->vehicle,
           vehicle_req => $slot->bike_requested };
   }

   my $page = $self->$_day_page( $req, $name, $rota_dt, $events, $slot_data );

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

sub slot : Role(rota_manager) Role(rider) Role(controller) Role(driver) {
   my ($self, $req) = @_;

   my $params = $req->uri_params;
   my $name   = $params->( 2 );
   my $args   = [ $params->( 0 ), $params->( 1 ), $name ];
   my $action = $req->query_params->( 'action' ); # claim or yield
   my $stash  = $self->dialog_stash( $req );
   my $href   = uri_for_action $req, $self->moniker.'/slot', $args;
   my $form   = $stash->{page}->{forms}->[ 0 ]
              = blank_form "${action}-slot", $href;
   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   if ($action eq 'claim') {
      my $role = $slot_type eq 'controller' ? 'controller'
               : $slot_type eq 'rider'      ? 'rider'
               : $slot_type eq 'driver'     ? 'driver'
                                            : FALSE;

      if ($role and is_member 'rota_manager', $req->session->roles) {
         my $person_rs = $self->schema->resultset( 'Person' );
         my $person    = $person_rs->find_by_shortcode( $req->username );
         my $opts      = { fields => { selected => $person } };
         my $people    = $person_rs->list_people( $role, $opts );

         p_select $form, 'assignee', [ [ NUL, NUL ], @{ $people } ];
      }

      $slot_type eq 'rider' and p_checkbox $form, 'request_bike', TRUE
   }

   p_button $form, 'confirm', "${action}_slot", {
      class => 'button', container_class => 'right-last',
      tip => make_tip $req, "${action}_slot_tip", [ $slot_type ] };

   return $stash;
}

sub yield_slot_action : Role(rota_manager) Role(rider) Role(controller)
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
   my $location = uri_for_action $req, $self->moniker.'/day_rota', $args;
   my $label    = slot_identifier $rota_name, $rota_date,
                                  $shift_type, $slot_type, $subslot;
   my $message  = [ to_msg '[_1] yielded slot [_2]', $person->label, $label ];

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::DayRota - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::DayRota;
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
