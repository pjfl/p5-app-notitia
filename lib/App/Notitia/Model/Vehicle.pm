package App::Notitia::Model::Vehicle;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TILDE TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind create_button
                                delete_button field_options loc
                                management_button register_action_paths
                                save_button set_element_focus
                                slot_identifier uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Time       qw( str2date_time );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'asset';

register_action_paths
   'asset/assign'   => 'vehicle/assign',
   'asset/unassign' => 'vehicle/assign',
   'asset/vehicle'  => 'vehicle',
   'asset/vehicles' => 'vehicles';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;
   $stash->{page}->{location} //= 'admin';

   return $stash;
};

# Private class attributes
my $_vehicle_links_cache = {};

# Private functions
my $_make_tip = sub {
   my ($req, $k, $args) = @_; $args //= [];

   return loc( $req, 'Hint' ).SPC.TILDE.SPC.loc( $req, $k, $args );
};

my $_confirm_vehicle_button = sub {
   my ($req, $action) = @_;

   my $tip   = loc( $req, 'Hint' ).SPC.TILDE.SPC
             . loc( $req, "confirm_${action}_tip", [ 'vehicle' ] );
   my $value = "${action}_vehicle";

   # Have left tip off as too noisey
   return { class => 'right-last', label => 'confirm', value => $value };
};

my $_vehicles_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "vehicles_heading_${_}" ) } } 0 .. 1 ];
};

my $_vehicle_type_tuple = sub {
   my ($type, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{selected} //= NUL;
   $opts->{selected}   = $opts->{selected} eq $type ? TRUE : FALSE;

   return [ $type->name, $type, $opts ];
};

# Private methods
my $_add_vehicle_js = sub {
   my $self = shift; my $opts = { domain => 'schedule', form => 'Vehicle' };

   return [ $self->check_field_server( 'vrn', $opts ) ];
};

my $_bind_vehicle_fields = sub {
   my ($self, $req, $vehicle, $opts) = @_; $opts //= {};

   my $disabled =  $opts->{disabled} // FALSE;
   my $map      =  {
      aquired   => { disabled => $disabled },
      disposed  => { disabled => $disabled },
      name      => { disabled => $disabled,
                     label    => 'vehicle_name',
                     tip      => $_make_tip->( $req, 'vehicle_name_field_tip')},
      notes     => { class    => 'standard-field autosize',
                     disabled => $disabled },
      vrn       => { class    => 'standard-field server',
                     disabled => $disabled },
   };

   return $self->bind_fields( $vehicle, $map, 'Vehicle' );
};

my $_list_vehicle_types = sub {
   my ($self, $opts) = @_; $opts = { %{ $opts // {} } };

   my $fields  = delete $opts->{fields} // {};
   my $type_rs = $self->schema->resultset( 'Type' );

   return [ map { $_vehicle_type_tuple->( $_, $fields ) }
            $type_rs->list_vehicle_types( $opts )->all ];
};

my $_maybe_find_vehicle = sub {
   my ($self, $vrn) = @_; $vrn or return Class::Null->new;

   my $rs = $self->schema->resultset( 'Vehicle' );

   return $rs->find_vehicle_by( $vrn, { prefetch => [ 'type' ] } );
};

my $_select_owner_list = sub {
   my ($self, $vehicle) = @_; my $schema = $self->schema;

   my $opts   = { fields => { selected => $vehicle->owner } };
   my $people = $schema->resultset( 'Person' )->list_all_people( $opts );

   return bind 'owner_id', [ [ NUL, NUL ], @{ $people } ], { numify => TRUE };
};

my $_toggle_assignment = sub {
   my ($self, $req, $action) = @_;

   my $method    = "${action}_slot";
   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $slot_name = $params->( 2 );
   my $vrn       = $req->body_params->( 'vehicle' );
   my $schema    = $self->schema;
   my $vehicle   = $schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

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
         and $v = str2date_time $v, 'GMT';

      $vehicle->$attr( $v );
   }

   $v = $params->( 'owner_id', $opts ); $vehicle->owner_id( $v ? $v : undef );
   $v = $params->( 'type', $opts ); defined $v and $vehicle->type_id( $v );

   return;
};

my $_vehicle_links = sub {
   my ($self, $req, $vehicle) = @_; my $vrn = $vehicle->[ 1 ]->vrn;

   my $links = $_vehicle_links_cache->{ $vrn }; $links and return @{ $links };

   $links = [];

   for my $actionp (map { $self->moniker."/${_}" } 'vehicle') {
      push @{ $links }, { value => management_button( $req, $actionp, $vrn ) };
   }

   $_vehicle_links_cache->{ $vrn } = $links;

   return @{ $links };
};

my $_vehicle_type_list = sub {
   my ($self, $vehicle) = @_;

   my $opts   = { fields => { selected => $vehicle->type } };
   my $values = [ [ NUL, NUL ], @{ $self->$_list_vehicle_types( $opts ) } ];

   return bind 'type', $values, { label => 'vehicle_type', numify => TRUE };
};

# Public methods
sub assign : Role(asset_manager) {
   my ($self, $req) = @_;

   my $params = $req->uri_params;
   my $args   = [ $params->( 0 ), $params->( 1 ), $params->( 2 ) ];
   my $action = $req->query_params->( 'action' );
   my $stash  = $self->dialog_stash( $req, "${action}-vehicle" );
   my $page   = $stash->{page};
   my $fields = $page->{fields};

   if ($action eq 'assign') {
      my $where  = { service => TRUE, type => 'bike' };
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

sub assign_vehicle_action : Role(asset_manager) {
   return $_[ 0 ]->$_toggle_assignment( $_[ 1 ], 'assign' );
}

sub create_vehicle_action : Role(asset_manager) {
   my ($self, $req) = @_;

   my $vehicle  = $self->schema->resultset( 'Vehicle' )->new_result( {} );

   $self->$_update_vehicle_from_request( $req, $vehicle ); $vehicle->insert;

   my $vrn      = $vehicle->vrn;
   my $message  = [ 'Vehicle [_1] created by [_2]', $vrn, $req->username ];
   my $location = uri_for_action $req, $self->moniker.'/vehicle', [ $vrn ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_vehicle_action : Role(asset_manager) {
   my ($self, $req) = @_;

   my $vrn     = $req->uri_params->( 0 );
   my $vehicle = $self->schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

   $vehicle->delete;

   my $message  = [ 'Vehicle [_1] deleted by [_2]', $vrn, $req->username ];
   my $location = uri_for_action $req, $self->moniker.'/vehicles';

   return { redirect => { location => $location, message => $message } };
}

sub unassign_vehicle_action : Role(asset_manager) {
   return $_[ 0 ]->$_toggle_assignment( $_[ 1 ], 'unassign' );
}

sub update_vehicle_action : Role(asset_manager) {
   my ($self, $req) = @_;

   my $vrn     = $req->uri_params->( 0 );
   my $vehicle = $self->schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

   $self->$_update_vehicle_from_request( $req, $vehicle ); $vehicle->update;

   my $message = [ 'Vehicle [_1] updated by [_2]', $vrn, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub vehicle : Role(asset_manager) {
   my ($self, $req) = @_;

   my $action    =  $self->moniker.'/vehicle';
   my $vrn       =  $req->uri_params->( 0, { optional => TRUE } );
   my $vehicle   =  $self->$_maybe_find_vehicle( $vrn );
   my $page      =  {
      fields     => $self->$_bind_vehicle_fields( $req, $vehicle ),
      literal_js => $self->$_add_vehicle_js(),
      template   => [ 'contents', 'vehicle' ],
      title      => loc( $req, 'vehicle_management_heading' ), };
   my $fields    =  $page->{fields};

   if ($vrn) {
      $fields->{delete} = delete_button $req, $vrn, 'vehicle';
      $fields->{href  } = uri_for_action $req, $action, [ $vrn ];
   }

   $fields->{owner} = $self->$_select_owner_list( $vehicle );
   $fields->{type } = $self->$_vehicle_type_list( $vehicle );
   $fields->{save } = save_button $req, $vrn, 'vehicle';

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(asset_manager) {
   my ($self, $req) = @_;

   my $params    =  $req->query_params;
   my $type      =  $params->( 'type',    { optional => TRUE } );
   my $private   =  $params->( 'private', { optional => TRUE } ) || FALSE;
   my $service   =  $params->( 'service', { optional => TRUE } ) || FALSE;
   my $action    =  $self->moniker.'/vehicle';
   my $page      =  {
      fields     => {
         add     => create_button( $req, $action, 'vehicle' ),
         headers => $_vehicles_headers->( $req ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, $type ? "${type}_list_link"
                                     : 'vehicles_management_heading' ), };
   my $where     =  { private => $private, service => $service, type => $type };
   my $rs        =  $self->schema->resultset( 'Vehicle' );
   my $vehicles  =  $rs->list_vehicles( $where );
   my $rows      =  $page->{fields}->{rows};

   for my $vehicle (@{ $vehicles }) {
      push @{ $rows }, [ { value => $vehicle->[ 0 ] },
                         $self->$_vehicle_links( $req, $vehicle ) ];
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
