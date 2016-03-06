package App::Notitia::Model::Vehicle;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind create_button
                                delete_button field_options loc
                                management_button register_action_paths
                                save_button uri_for_action );
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
   'asset/vehicle'  => 'vehicle',
   'asset/vehicles' => 'vehicles';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Private class attributes
my $_vehicle_links_cache = {};

# Private functions
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
   my ($self, $vehicle, $opts) = @_; $opts //= {};

   my $disabled =  $opts->{disabled} // FALSE;
   my $map      =  {
      aquired   => { disabled => $disabled },
      disposed  => { disabled => $disabled },
      name      => { disabled => $disabled,  label    => 'vehicle_name' },
      notes     => { class    => 'autosize', disabled => $disabled },
      vrn       => { class    => 'server',   disabled => $disabled },
   };

   return $self->bind_fields( $vehicle, $map, 'Vehicle' );
};

my $_list_vehicle_types = sub {
   my ($self, $opts) = @_; $opts = { %{ $opts // {} } };

   my $fields  = delete $opts->{fields} // {};
   my $type_rs = $self->schema->resultset( 'Type' );

   return [ map { $_vehicle_type_tuple->( $_, $fields ) }
            $type_rs->search( { type    => 'vehicle'  },
                              { columns => [ 'id', 'name' ], %{ $opts } } )
                    ->all ];
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

   return bind( 'owner_id', [ [ NUL, NUL ], @{ $people } ], { numify => TRUE });
};

my $_update_vehicle_from_request = sub {
   my ($self, $req, $vehicle) = @_; my $params = $req->body_params; my $v;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   for my $attr (qw( aquired disposed name notes vrn )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      length $v and is_member $attr, [ qw( aquired disposed ) ]
         and $v = str2date_time( $v, 'GMT' );

      $vehicle->$attr( $v );
   }

   $v = $params->( 'owner_id', $opts ); $vehicle->owner_id( $v ? $v : undef );
   $v = $params->( 'type', $opts ); defined $v and $vehicle->type_id( $v );

   return;
};

my $_vehicle_links = sub {
   my ($self, $req, $name) = @_; my $links = $_vehicle_links_cache->{ $name };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( vehicle ) ) {
      my $href = uri_for_action( $req, $self->moniker."/${action}", [ $name ] );

      push @{ $links }, {
         value => management_button( $req, $name, $action, $href ) };
   }

   $_vehicle_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_vehicle_type_list = sub {
   my ($self, $vehicle) = @_;

   my $opts   = { fields => { selected => $vehicle->type } };
   my $types  = $self->$_list_vehicle_types( $opts );
   my $values = [ [ NUL, NUL ], @{ $types } ];

   return bind( 'type', $values, { label => 'vehicle_type', numify => TRUE } );
};

# Public methods
sub create_vehicle_action : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $vehicle  = $self->schema->resultset( 'Vehicle' )->new_result( {} );

   $self->$_update_vehicle_from_request( $req, $vehicle ); $vehicle->insert;

   my $vrn      = $vehicle->vrn;
   my $message  = [ 'Vehicle [_1] created by [_2]', $vrn, $req->username ];
   my $location = uri_for_action( $req, $self->moniker.'/vehicle', [ $vrn ] );

   return { redirect => { location => $location, message => $message } };
}

sub delete_vehicle_action : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->uri_params->( 0 );
   my $vehicle = $self->schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

   $vehicle->delete;

   my $message  = [ 'Vehicle [_1] deleted by [_2]', $vrn, $req->username ];
   my $location = uri_for_action( $req, $self->moniker.'/vehicles' );

   return { redirect => { location => $location, message => $message } };
}

sub update_vehicle_action : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $vrn     = $req->uri_params->( 0 );
   my $vehicle = $self->schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );

   $self->$_update_vehicle_from_request( $req, $vehicle ); $vehicle->update;

   my $message = [ 'Vehicle [_1] updated by [_2]', $vrn, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub vehicle : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $action    =  $self->moniker.'/vehicle';
   my $vrn       =  $req->uri_params->( 0, { optional => TRUE } );
   my $vehicle   =  $self->$_maybe_find_vehicle( $vrn );
   my $page      =  {
      fields     => $self->$_bind_vehicle_fields( $vehicle ),
      literal_js => $self->$_add_vehicle_js(),
      template   => [ 'contents', 'vehicle' ],
      title      => loc( $req, 'vehicle_management_heading' ), };
   my $fields    =  $page->{fields};

   if ($vrn) {
      $fields->{delete} = delete_button( $req, $vrn, 'vehicle' );
      $fields->{href  } = uri_for_action( $req, $action, [ $vrn ] );
   }

   $fields->{owner} = $self->$_select_owner_list( $vehicle );
   $fields->{type } = $self->$_vehicle_type_list( $vehicle );
   $fields->{save } = save_button( $req, $vrn, 'vehicle' );

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $page    =  {
      fields   => { headers => $_vehicles_headers->( $req ), rows => [], },
      template => [ 'contents', 'table' ],
      title    => loc( $req, 'vehicles_management_heading' ), };
   my $opts    =  { order_by => 'vrn', prefetch => [ 'owner' ] };
   my $rs      =  $self->schema->resultset( 'Vehicle' );
   my $action  =  $self->moniker.'/vehicle';
   my $rows    =  $page->{fields}->{rows};

   for my $vehicle (@{ $rs->list_all_vehicles( $opts ) }) {
      push @{ $rows },
         [ { value => $vehicle->[ 0 ] },
           $self->$_vehicle_links( $req, $vehicle->[ 1 ]->vrn ) ];
   }

   $page->{fields}->{add} = create_button( $req, $action, 'vehicle' );

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
