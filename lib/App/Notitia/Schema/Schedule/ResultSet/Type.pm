package App::Notitia::Schema::Schedule::ResultSet::Type;

use strictures;
use parent 'DBIx::Class::ResultSet';

use Class::Usul::Functions qw( throw );
use HTTP::Status           qw( HTTP_EXPECTATION_FAILED );

# Private class attributes
my $_types = {};

# Private methods
my $_find_by = sub {
   my ($self, $name, $type_class, $opts) = @_; $opts //= {};

   my $k = "${name}-${type_class}"; exists $_types->{ $k }
      and return $_types->{ $k };

   my $label = delete $opts->{label} // ucfirst $type_class;
   my $type  = $self->search
      ( { 'name' => $name, 'type_class' => $type_class }, $opts )->single
      or throw "${label} type [_1] not found", [ $name ],
               level => 3, rv => HTTP_EXPECTATION_FAILED;

   return $_types->{ $k } = $type;
};

# Public methods
sub find_certification_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'certification' );
}

sub find_role_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'role' );
}

sub find_rota_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'rota' );
}

sub find_type_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], $_[ 2 ] );
}

sub find_vehicle_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'vehicle' );
}

sub list_all_types {
   my ($self, $opts) = @_; $opts //= {};

   $opts->{order_by} //= [ 'type_class', 'name' ];

   return $self->search
      ( {}, { columns => [ 'name', 'type_class' ], %{ $opts } } );
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

sub list_rota_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'rota' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub list_types {
   my ($self, $type_class, $opts) = @_; $opts //= {};

   $opts->{order_by} //= [ 'type_class', 'name' ];

   return $self->search
      ( { type_class => $type_class },
        { columns    => [ 'id', 'name', 'type_class' ], %{ $opts } } );
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
