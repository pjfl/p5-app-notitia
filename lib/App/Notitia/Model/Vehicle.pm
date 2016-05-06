package App::Notitia::Model::Vehicle;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( assign_link bind bind_fields button
                                check_field_js create_link delete_button
                                loc make_tip management_link
                                register_action_paths save_button
                                set_element_focus slot_identifier time2int to_dt
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use DateTime;
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'asset';

register_action_paths
   'asset/assign'          => 'vehicle-assign',
   'asset/request_vehicle' => 'vehicle-request',
   'asset/unassign'        => 'vehicle-assign',
   'asset/vehicle'         => 'vehicle',
   'asset/vehicle_events'  => 'vehicle-events',
   'asset/vehicles'        => 'vehicles';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav }->{list    }   = $self->admin_navigation_links( $req );
   $stash->{page}->{location} //= 'admin';

   return $stash;
};

# Private functions
my $_add_vehicle_js = sub {
   my $vrn  = shift;
   my $opts = { domain => $vrn ? 'update' : 'insert', form => 'Vehicle' };

   return [ check_field_js( 'vrn', $opts ) ];
};

my $_bind_request_fields = sub {
   my ($schema, $req, $event, $opts) = @_; $opts //= {};

   my $map =  {
      name => { class => 'standard-field', disabled => TRUE,
                label => 'event_name' },
   };

   return bind_fields $schema, $event, $map, 'Event';
};

my $_bind_vehicle_fields = sub {
   my ($schema, $req, $vehicle, $opts) = @_; $opts //= {};

   my $disabled =  $opts->{disabled} // FALSE;
   my $map      =  {
      aquired   => { disabled => $disabled },
      disposed  => { class    => 'standard-field clearable',
                     disabled => $disabled },
      name      => { disabled => $disabled,
                     label    => 'vehicle_name',
                     tip      => make_tip( $req, 'vehicle_name_field_tip') },
      notes     => { class    => 'standard-field autosize',
                     disabled => $disabled },
      vrn       => { class    => 'standard-field server',
                     disabled => $disabled },
   };

   return bind_fields $schema, $vehicle, $map, 'Vehicle';
};

my $_compare_datetimes = sub {
   my ($x, $y) = @_;

   $x->[ 0 ] < $y->[ 0 ] and return -1; $x->[ 0 ] > $y->[ 0 ] and return 1;

   $x = time2int $x->[ 1 ]->[ 1 ]->{value};
   $y = time2int $y->[ 1 ]->[ 1 ]->{value};

   $x < $y and return -1; $x > $y and return 1; return 0;
};

my $_confirm_vehicle_button = sub {
   return button $_[ 0 ],
     { class => 'right-last', label => 'confirm', value => $_[ 1 ].'_vehicle' };
};

my $_find_vreq_by = sub {
   my ($schema, $event, $vehicle_type) = @_;

   my $rs = $schema->resultset( 'VehicleRequest' );

   return $rs->search( { event_id => $event->id,
                         type_id  => $vehicle_type->id } )->single;
};

my $_maybe_find_vehicle = sub {
   my ($schema, $vrn) = @_; $vrn or return Class::Null->new;

   my $rs = $schema->resultset( 'Vehicle' );

   return $rs->find_vehicle_by( $vrn, { prefetch => [ 'type' ] } );
};

my $_owner_list = sub {
   my ($schema, $vehicle) = @_;

   my $opts   = { fields => { selected => $vehicle->owner } };
   my $people = $schema->resultset( 'Person' )->list_all_people( $opts );

   return bind 'owner_id', [ [ NUL, NUL ], @{ $people } ], { numify => TRUE };
};

my $_quantity_list = sub {
   my ($type, $selected) = @_;

   my $opts   = { class => 'single-digit',
                  label => NUL, type => 'select' };
   my $values = [ [ 0, 0 ], [ 1, 1 ], [ 2, 2 ], [ 3, 3 ], [ 4, 4 ], ];

   $values->[ $selected ]->[ 2 ] = { selected => TRUE };

   return { class => 'single-digit-select narrow',
            value => bind( "${type}_quantity", $values, $opts ) };
};

my $_transport_links = sub {
   my ($self, $req, $event) = @_; my @links;

   my $moniker = $self->moniker; my $uri = $event->uri;

   push @links, {
      value => management_link
         ( $req, "${moniker}/request_vehicle", 'edit', { args => [ $uri ] } ) };

   return @links;
};

my $_update_vehicle_req_from_request = sub {
   my ($req, $vreq, $vehicle_type) = @_;

   my $v = $req->body_params->( "${vehicle_type}_quantity" );

   defined $v and $vreq->quantity( $v );

   return;
};

my $_vehicle_events_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "vehicle_events_heading_${_}" ) } }
            0 .. 3 ];
};

my $_vehicle_event_links = sub {
   my ($self, $req, $event) = @_; my @links;

   my $uri = $event->uri; my $vrn = $event->vehicle->vrn;

   push @links, {
      value => management_link
         ( $req, 'event/vehicle_event', 'edit', { args => [ $vrn, $uri ] } ) };

   return @links;
};

my $_vehicle_slot_links = sub {
   my ($self, $req, $slot) = @_; my @links;

   my $type = $slot->rota_type;
   my $date = $slot->date->clone->set_time_zone( 'local' )->ymd;

   push @links, {
      value => management_link
         ( $req, 'sched/day_rota', 'edit', { args => [ $type, $date ] } ) };

   return @links;
};

my $_vehicle_links = sub {
   my ($moniker, $req, $service, $vehicle) = @_;

   my $vrn = $vehicle->[ 1 ]->vrn; my $links = [];

   push @{ $links },
      { value => management_link( $req, "${moniker}/vehicle", $vrn ) };

   if ($service) {
      my $now = DateTime->now;

      push @{ $links },
         { value => create_link
              ( $req, 'event/vehicle_event', 'event', { args => [ $vrn ] } ) };

      push @{ $links },
         { value => management_link
              ( $req, "${moniker}/vehicle_events", $vrn,
                { params => { after => $now->subtract( days => 1 )->ymd } } ) };
   }

   return @{ $links };
};

my $_vehicle_request_button = sub {
   return button $_[ 0 ], { class => 'save-button right-last' },
             'request', 'vehicle', [ $_[ 1 ] ];
};

my $_vehicle_request_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "vehicle_request_heading_${_}" ) } }
            0 .. 5 ];
};

my $_vehicle_title = sub {
   my ($req, $type, $private, $service) = @_;

   my $k = 'vehicles_management_heading';

   if    ($private) { $k = 'vehicle_private_heading' }
   elsif ($service) { $k = 'vehicle_service_heading' }
   elsif ($type)    { $k = "${type}_list_link" }

   return loc $req, $k;
};

my $_vehicle_type_tuple = sub {
   my ($type, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{selected} //= NUL;
   $opts->{selected}   = $opts->{selected} eq $type ? TRUE : FALSE;

   return [ $type->name, $type, $opts ];
};

my $_vehicles_headers = sub {
   my ($req, $service) = @_; my $max = $service ? 3 : 1;

   return [ map { { value => loc( $req, "vehicles_heading_${_}" ) } }
            0 .. $max ];
};

my $_find_or_create_vreq = sub {
   my ($schema, $event, $vehicle_type) = @_;

   my $vreq = $_find_vreq_by->( $schema, $event, $vehicle_type );

   $vreq and return $vreq; my $rs = $schema->resultset( 'VehicleRequest' );

   return $rs->new_result( { event_id => $event->id,
                             type_id  => $vehicle_type->id } );
};

my $_list_vehicle_types = sub {
   my ($schema, $opts) = @_; $opts = { %{ $opts // {} } };

   my $fields  = delete $opts->{fields} // {};
   my $type_rs = $schema->resultset( 'Type' );

   return [ map { $_vehicle_type_tuple->( $_, $fields ) }
            $type_rs->list_vehicle_types( $opts )->all ];
};

my $_req_quantity = sub {
   my ($schema, $event, $vehicle_type) = @_;

   my $vreq = $_find_vreq_by->( $schema, $event, $vehicle_type );

   return $vreq ? $vreq->quantity : 0;
};

my $_vehicle_type_list = sub {
   my ($schema, $vehicle) = @_;

   my $opts   = { fields => { selected => $vehicle->type } };
   my $values = [ [ NUL, NUL ], @{ $_list_vehicle_types->( $schema, $opts ) } ];

   return bind 'type', $values, { label => 'vehicle_type', numify => TRUE };
};

my $_vreq_row = sub {
   my ($schema, $req, $page, $event, $vehicle_type) = @_;

   my $uri    = $page->{event_uri};
   my $tports = $schema->resultset( 'Transport' )->search_for_vehicle_by_type
      ( $event->id, $vehicle_type->id );
   my $quant  = $_req_quantity->( $schema, $event, $vehicle_type );
   my $row    = [ { value => loc( $req, $vehicle_type ) },
                  $_quantity_list->( $vehicle_type, $quant ) ];

   $quant or return $row;

   for my $slotno (0 .. $quant - 1) {
      my $transport = $tports->next;
      my $vehicle   = $transport ? $transport->vehicle : undef;
      my $opts      = { name        => "${vehicle_type}_event_${slotno}",
                        operator    => $event->owner,
                        type        => $vehicle_type,
                        vehicle     => $vehicle,
                        vehicle_req => TRUE, };

      push @{ $row }, assign_link( $req, $page, [ $uri ], $opts );
   }

   return $row;
};

# Private methods
my $_toggle_event_assignment = sub {
   my ($self, $req, $action) = @_;

   my $schema   = $self->schema;
   my $uri      = $req->uri_params->( 0 );
   my $vrn      = $req->body_params->( 'vehicle' );
   my $vehicle  = $schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );
   my $method   = $action eq 'assign'
                ? 'assign_to_event' : 'unassign_from_event';

   $vehicle->$method( $uri, $req->username );

   my $actionp  = $self->moniker.'/request_vehicle';
   my $message  = [ "Vehicle [_1] ${action}ed to [_2] by [_3]",
                    $vrn, $uri, $req->username ];
   my $location = uri_for_action( $req, $actionp, [ $uri ] );

   return { redirect => { location => $location, message => $message } };
};

my $_toggle_assignment = sub {
   my ($self, $req, $action) = @_;

   my $params = $req->uri_params; my $rota_name = $params->( 0 ); my $r;

   try   { $self->schema->resultset( 'Type' )->find_rota_by( $rota_name ) }
   catch { $r = $self->$_toggle_event_assignment( $req, $action ) };

   $r and return $r;

   my $rota_date = $params->( 1 );
   my $slot_name = $params->( 2 );
   my $vrn       = $req->body_params->( 'vehicle' );
   my $schema    = $self->schema;
   my $vehicle   = $schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );
   my $method    = "${action}_slot";

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $slot_name, 3;

   $vehicle->$method( $rota_name, $rota_date, $shift_type,
                      $slot_type, $subslot, $req->username );

   my $label     = slot_identifier
      ( $rota_name, $rota_date, $shift_type, $slot_type, $subslot );
   my $message   = [ "Vehicle [_1] ${action}ed to [_2] by [_3]",
                     $vrn, $label, $req->username ];
   my $location  = uri_for_action
      ( $req, 'sched/day_rota', [ $rota_name, $rota_date, $slot_name ] );

   return { redirect => { location => $location, message => $message } };
};

my $_update_vehicle_from_request = sub {
   my ($self, $req, $vehicle) = @_; my $params = $req->body_params; my $v;

   my $opts = { optional => TRUE };

   for my $attr (qw( aquired disposed name notes vrn )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      length $v and is_member $attr, [ qw( aquired disposed ) ]
         and $v = to_dt $v;

      $vehicle->$attr( $v );
   }

   $v = $params->( 'owner_id', $opts ); $vehicle->owner_id( $v ? $v : undef );
   $v = $params->( 'type', $opts ); defined $v and $vehicle->type_id( $v );

   return;
};

my $_vehicle_events = sub {
   my ($self, $req, $opts) = @_; my @rows;

   my $event_rs = $self->schema->resultset( 'Event' );
   my $slot_rs  = $self->schema->resultset( 'Slot' );
   my $tport_rs = $self->schema->resultset( 'Transport' );

   for my $event ($event_rs->search_for_events( $opts )->all) {
      push @rows,
         [ $event->start_date,
           [ { value => $event->label },
             { value => $event->start_time },
             { value => $event->end_time },
             $self->$_vehicle_event_links( $req, $event ) ] ];
   }

   for my $slot ($slot_rs->search_for_assigned_slots( $opts )->all) {
      push @rows,
         [ $slot->date,
           [ { value => $slot->label( $req ) },
             { value => $slot->start_time },
             { value => $slot->end_time },
             $self->$_vehicle_slot_links( $req, $slot ) ] ];
   }

   for my $tport ($tport_rs->search_for_assigned_vehicles( $opts )->all) {
      my $event = $tport->event;

      push @rows,
         [ $event->start_date,
           [ { value => $event->label },
             { value => $event->start_time },
             { value => $event->end_time },
             $self->$_transport_links( $req, $event ) ] ];
   }

   return [ map { $_->[ 1 ] } sort { $_compare_datetimes->( $a, $b ) } @rows ];
};

# Public methods
sub assign : Role(rota_manager) {
   my ($self, $req) = @_; my $params = $req->uri_params;

   my $args = [ $params->( 0 ) ]; my $opts = { optional => TRUE };

   my $rota_date = $params->( 1, $opts );
      $rota_date and push @{ $args }, $rota_date;

   my $slot_name = $params->( 2, $opts );
      $slot_name and push @{ $args }, $slot_name;

   my $action = $req->query_params->( 'action' );
   my $type   = $req->query_params->( 'type', { optional => TRUE } ) // 'bike';
   my $stash  = $self->dialog_stash( $req, "${action}-vehicle" );
   my $page   = $stash->{page};
   my $fields = $page->{fields};

   if ($action eq 'assign') {
      my $where  = { service => TRUE, type => $type };
      my $rs     = $self->schema->resultset( 'Vehicle' );
      my $values = [ [ NUL, NUL ], @{ $rs->list_vehicles( $where ) } ];

      $fields->{vehicle}
         = bind 'vehicle', $values, { class => 'right-last', label => NUL };
      $page->{literal_js} = set_element_focus 'assign-vehicle', 'vehicle';
   }
   else {
      my $vrn = $req->query_params->( 'vehicle' );

      $fields->{vehicle} = { name => 'vehicle', value => $vrn };
   }

   $fields->{href   } = uri_for_action $req, $self->moniker.'/vehicle', $args;
   $fields->{confirm} = $_confirm_vehicle_button->( $req, $action );
   $fields->{assign } = bind $action, $action, { class => 'right' };

   return $stash;
}

sub assign_vehicle_action : Role(rota_manager) {
   return $_[ 0 ]->$_toggle_assignment( $_[ 1 ], 'assign' );
}

sub create_vehicle_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vehicle = $self->schema->resultset( 'Vehicle' )->new_result( {} );

   $self->$_update_vehicle_from_request( $req, $vehicle );

   try { $vehicle->insert }
   catch {
      $self->application->debug and throw $_; $self->log->error( $_ );
      throw 'Vehicle [_1] failed to create', [ $vehicle->vrn ];
   };

   my $vrn      = $vehicle->vrn;
   my $message  = [ 'Vehicle [_1] created by [_2]', $vrn, $req->username ];
   my $location = uri_for_action $req, $self->moniker.'/vehicle', [ $vrn ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_vehicle_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn     = $req->uri_params->( 0 );
   my $vehicle = $self->schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

   $vehicle->delete;

   my $message  = [ 'Vehicle [_1] deleted by [_2]', $vrn, $req->username ];
   my $location = uri_for_action $req, $self->moniker.'/vehicles';

   return { redirect => { location => $location, message => $message } };
}

sub request_vehicle : Role(rota_manager) Role(event_manager) {
   my ($self, $req) = @_;

   my $schema    =  $self->schema;
   my $uri       =  $req->uri_params->( 0 );
   my $event     =  $schema->resultset( 'Event' )->find_event_by
                    ( $uri, { prefetch => [ 'owner' ] } );
   my $page      =  {
      event_uri  => $uri,
      fields     => $_bind_request_fields->( $schema, $req, $event ),
      moniker    => $self->moniker,
      template   => [ 'contents', 'vehicle-request' ],
      title      => loc( $req, 'vehicle_request_heading' ), };
   my $type_rs   =  $schema->resultset( 'Type' );
   my $opts      =  { disabled => TRUE };
   my $fields    =  $page->{fields};

   $fields->{action  } = uri_for_action $req, 'asset/vehicle', [ $uri ];
   $fields->{date    } = bind 'event_date', $event->start_date, $opts;
   $fields->{request } = $_vehicle_request_button->( $req, $event );
   $fields->{vehicles} = { class   => 'smaller-table',
                           headers => $_vehicle_request_headers->( $req ) };

   for my $vehicle_type ($type_rs->list_types( 'vehicle' )->all) {
      my $row = $_vreq_row->( $schema, $req, $page, $event, $vehicle_type );

      push @{ $fields->{vehicles}->{rows} }, $row;
   }

   return $self->get_stash( $req, $page );
}

sub request_vehicle_action : Role(event_manager) {
   my ($self, $req) = @_;

   my $schema  = $self->schema;
   my $uri     = $req->uri_params->( 0 );
   my $event   = $schema->resultset( 'Event' )->find_event_by( $uri );
   my $type_rs = $schema->resultset( 'Type' );

   for my $vehicle_type ($type_rs->list_types( 'vehicle' )->all) {
      my $vreq = $_find_or_create_vreq->( $schema, $event, $vehicle_type );

      $_update_vehicle_req_from_request->( $req, $vreq, $vehicle_type );

      if ($vreq->in_storage) { $vreq->update } else { $vreq->insert }
   }

   my $actionp  = $self->moniker.'/request_vehicle';
   my $location = uri_for_action $req, $actionp, [ $uri ];
   my $message  = [ 'Vehicle request for event [_1] updated by [_2]',
                    $event, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub unassign_vehicle_action : Role(rota_manager) {
   return $_[ 0 ]->$_toggle_assignment( $_[ 1 ], 'unassign' );
}

sub update_vehicle_action : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn     = $req->uri_params->( 0 );
   my $vehicle = $self->schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

   $self->$_update_vehicle_from_request( $req, $vehicle );

   try   { $vehicle->update }
   catch {
      $self->application->debug and throw $_; $self->log->error( $_ );
      throw 'Vehicle [_1] failed to update', [ $vehicle->vrn ];
   };

   my $message = [ 'Vehicle [_1] updated by [_2]', $vrn, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub vehicle : Role(rota_manager) {
   my ($self, $req) = @_;

   my $schema     =  $self->schema;
   my $actionp    =  $self->moniker.'/vehicle';
   my $vrn        =  $req->uri_params->( 0, { optional => TRUE } );
   my $vehicle    =  $_maybe_find_vehicle->( $schema, $vrn );
   my $page       =  {
      fields      => $_bind_vehicle_fields->( $schema, $req, $vehicle ),
      first_field => 'vrn',
      literal_js  => $_add_vehicle_js->( $vrn ),
      template    => [ 'contents', 'vehicle' ],
      title       => loc( $req, $vrn ? 'vehicle_edit_heading'
                                     : 'vehicle_create_heading' ), };
   my $fields     =  $page->{fields};

   if ($vrn) {
      $fields->{delete} = delete_button $req, $vrn, { type => 'vehicle' };
      $fields->{href  } = uri_for_action $req, $actionp, [ $vrn ];
      $fields->{links } = create_link $req, $actionp, 'vehicle',
                             { container_class => 'add-link right' };
   }

   $fields->{owner} = $_owner_list->( $schema, $vehicle );
   $fields->{type } = $_vehicle_type_list->( $schema, $vehicle );
   $fields->{save } = save_button $req, $vrn, { type => 'vehicle' };

   return $self->get_stash( $req, $page );
}

sub vehicle_events : Role(rota_manager) {
   my ($self, $req) = @_;

   my $vrn          =  $req->uri_params->( 0 );
   my $params       =  $req->query_params;
   my $after        =  $params->( 'after',  { optional => TRUE } );
   my $before       =  $params->( 'before', { optional => TRUE } );
   my $opts         =  { after      => $after  ? to_dt( $after  ) : FALSE,
                         before     => $before ? to_dt( $before ) : FALSE,
                         event_type => 'vehicle',
                         vehicle    => $vrn, };
   my $page         =  {
      fields        => {
         events     => {
            headers => $_vehicle_events_headers->( $req ),
            rows    => $self->$_vehicle_events( $req, $opts ), },
         links      => create_link
            ( $req, 'event/vehicle_event', 'event',
              { args => [ $vrn ], container_class => 'add-link right-last' } ),
         name       => bind 'vehicle', $vrn, { disabled => TRUE }, },
      template      => [ 'contents', 'vehicle-events' ],
      title         => loc( $req, 'vehicle_events_management_heading' ), };

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(rota_manager) {
   my ($self, $req) = @_;

   my $params    =  $req->query_params;
   my $type      =  $params->( 'type',    { optional => TRUE } );
   my $private   =  $params->( 'private', { optional => TRUE } ) || FALSE;
   my $service   =  $params->( 'service', { optional => TRUE } ) || FALSE;
   my $actionp   =  $self->moniker.'/vehicle';
   my $page      =  {
      fields     => {
         headers => $_vehicles_headers->( $req, $service ),
         links   => create_link( $req, $actionp, 'vehicle' ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => $_vehicle_title->( $req, $type, $private, $service ), };
   my $where     =  { private => $private, service => $service, type => $type };
   my $rs        =  $self->schema->resultset( 'Vehicle' );
   my $rows      =  $page->{fields}->{rows};

   for my $vehicle (@{ $rs->list_vehicles( $where ) }) {
      push @{ $rows }, [ { value => $vehicle->[ 0 ] },
               $_vehicle_links->( $self->moniker, $req, $service, $vehicle ) ];
   }

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Vehicle - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Vehicle;
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
