package App::Notitia::Model::Vehicle;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind delete_button
                                field_options loc register_action_paths
                                save_button uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( throw );
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
my $_add_vehicle_button = sub {
   my ($req, $action) = @_;

   return { class => 'fade',
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $action ),
            name  => 'create_vehicle',
            tip   => loc( $req, 'vehicle_create_tip', [ 'vehicle' ] ),
            type  => 'link',
            value => loc( $req, 'vehicle_create_link' ) };
};

my $_vehicles_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "vehicles_heading_${_}" ) } } 0 .. 1 ];
};

# Private methods
my $_vehicle_links = sub {
   my ($self, $req, $name) = @_; my $links = $_vehicle_links_cache->{ $name };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( vehicle ) ) {
      my $href = uri_for_action( $req, $self->moniker."/${action}", [ $name ] );

      push @{ $links }, {
         value => { class => 'table-link fade',
                    hint  => loc( $req, 'Hint' ),
                    href  => $href,
                    name  => "${name}-${action}",
                    tip   => loc( $req, "${action}_management_tip" ),
                    type  => 'link',
                    value => loc( $req, "${action}_management_link" ), }, };
   }

   $_vehicle_links_cache->{ $name } = $links;

   return @{ $links };
};

# Public methods
sub create_vehicle_action : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->body_params->( 'vrn' );
   my $message  = [ 'Vehicle [_1] created by [_2]', $vrn, $req->username ];
   my $location = uri_for_action( $req, $self->moniker.'/vehicle', [ $vrn ] );

   return { redirect => { location => $location, message => $message } };
}

sub delete_vehicle_action : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $vrn      = $req->uri_params->( 0 );
   my $message  = [ 'Vehicle [_1] deleted by [_2]', $vrn, $req->username ];
   my $location = uri_for_action( $req, $self->moniker.'/vehicles' );

   return { redirect => { location => $location, message => $message } };
}

sub update_vehicle_action : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $vrn     = $req->uri_params->( 0 );
   my $message = [ 'Vehicle [_1] updated by [_2]', $vrn, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub vehicle : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $page    =  {
      fields   => {},
      template => [ 'contents', 'vehicle' ],
      title    => loc( $req, 'vehicle_management_heading' ), };

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $page    =  {
      fields   => { headers => $_vehicles_headers->( $req ), rows => [], },
      template => [ 'contents', 'table' ],
      title    => loc( $req, 'vehicles_management_heading' ), };
   my $rs      =  $self->schema->resultset( 'Vehicle' );
   my $action  =  $self->moniker.'/vehicle';
   my $rows    =  $page->{fields}->{rows};

   for my $vehicle (@{ $rs->list_all_vehicles( { order_by => 'vrn' } ) }) {
      push @{ $rows },
         [ { value => $vehicle->[ 0 ] },
           $self->$_vehicle_links( $req, $vehicle->[ 1 ]->vrn ) ];
   }

   $page->{fields}->{add} = $_add_vehicle_button->( $req, $action );

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
