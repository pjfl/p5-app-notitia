package App::Notitia::Schema::Schedule::ResultSet::Vehicle;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );

# Private functions
my $_field_tuple = sub {
   my ($vehicle, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{selected} //= NUL;
   $opts->{selected}   = $opts->{selected} eq $vehicle ? TRUE : FALSE;

   return [ $vehicle->label, $vehicle, $opts ];
};

# Private methods
my $_find_owner = sub {
   my ($self, $scode) = @_; my $schema = $self->result_source->schema;

   my $opts = { columns => [ 'id' ] };

   return $schema->resultset( 'Person' )->find_by_shortcode( $scode, $opts );
};

my $_find_vehicle_type = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_vehicle_by( $name );
};

# Public methods
sub new_result {
   my ($self, $columns) = @_;

   my $type = delete $columns->{type};

   $type and $columns->{type_id} = $self->$_find_vehicle_type( $type )->id;

   my $owner = delete $columns->{owner};

   $owner and $columns->{owner_id} = $self->$_find_owner( $owner )->id;

   return $self->next::method( $columns );
}

sub find_vehicle_by {
   my ($self, $vrn, $opts) = @_; $opts //= {};

   my $vehicle = $self->search( { 'vrn' => $vrn }, $opts )->single;

   defined $vehicle or throw 'Vehicle [_1] not found', [ $vrn ];

   return $vehicle;
}

sub list_vehicles {
   my ($self, $opts) = @_;

   my $vehicles = $self->search_for_vehicles( $opts );

   return [ map { $_field_tuple->( $_, $opts->{fields} ) } $vehicles->all ];
}

sub search_for_vehicles {
   my ($self, $opts) = @_;

   $opts = { columns  => [ 'colour', 'id', 'name', 'vrn' ], order_by => 'vrn',
             prefetch => [ 'type', 'owner' ], %{ $opts } };
   delete $opts->{fields};

   my $where = {};
   my $type  = delete $opts->{type}; $type
      and $where->{ 'type.name' } = $type;
   my $owner = delete $opts->{owner}; $owner
      and $where->{owner_id} = $owner->id;

   ($opts->{private} or $opts->{service} or $owner)
      and $where->{disposed} = { '=' => undef };
   delete $opts->{private} and $where->{owner_id} = { '!=' => undef };
   delete $opts->{service} and $where->{owner_id} = { '='  => undef };

   return $self->search( $where, $opts );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Vehicle - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Vehicle;
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
