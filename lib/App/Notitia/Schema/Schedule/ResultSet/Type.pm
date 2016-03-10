package App::Notitia::Schema::Schedule::ResultSet::Type;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );

# Private class attributes
my $_types = {};

# Private methods
my $_find_by = sub {
   my ($self, $name, $type_class, $label) = @_;

   $label //= ucfirst $type_class;
   # TODO: Why does this have to be a hashref and not a list?
   #       Maybe the enum or is because 'type' is a reserved word in SQL
   my $type = $self->find( { name => $name, type_class => $type_class } );

   $type or throw "${label} type [_1] not found", [ $name ],
                  level => 3, rv => HTTP_EXPECTATION_FAILED;

   return $type;
};

# Public methods
sub find_certification_by {
   my ($self, $name) = @_; my $k = "cert-${name}";

   exists $_types->{ $k } and return $_types->{ $k };

   my $type = $self->$_find_by( $name, 'certification' );

   return $_types->{ $k } = $type;
}

sub find_role_by {
   my ($self, $name) = @_; my $k = "role-${name}";

   exists $_types->{ $k } and return $_types->{ $k };

   my $type = $self->$_find_by( $name, 'role' );

   return $_types->{ $k } = $type;
}

sub find_rota_by {
   my ($self, $name) = @_; my $k = "rota-${name}";

   exists $_types->{ $k } and return $_types->{ $k };

   my $type = $self->$_find_by( $name, 'rota' );

   return $_types->{ $k } = $type;
}

sub find_vehicle_by {
   my ($self, $name) = @_; my $k = "vehicle-${name}";

   exists $_types->{ $k } and return $_types->{ $k };

   my $type = $self->$_find_by( $name, 'vehicle' );

   return $_types->{ $k } = $type;
}

sub list_certification_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'certification' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub list_role_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'role' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub list_vehicle_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'vehicle' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Type - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Type;
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
