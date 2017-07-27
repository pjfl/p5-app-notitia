package App::Notitia::Schema::Schedule::ResultSet::Type;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use Unexpected::Functions   qw( Unspecified );

# Private class attributes
my $_types = {};

# Private methods
my $_find_by = sub {
   my ($self, $name, $type_class, $opts) = @_; $opts //= {};

   $type_class or throw Unspecified, [ 'type class' ];
   $name or throw Unspecified, [ "type name for class ${type_class}" ];

# TODO: Implement cache invalidation when a type is removed
   my $k = "${name}-${type_class}"; exists $_types->{ $k }
      and return $_types->{ $k };

   my $label = delete $opts->{label} // ucfirst $type_class;
   my $type  = $self->search
      ( { 'name' => $name, 'type_class' => $type_class }, $opts )->single;

   defined $type or throw "${label} type [_1] not found", [ $name ], level => 3;

   return $_types->{ $k } = $type;
};

my $_type_tuple = sub {
   my ($type, $opts) = @_; $opts = { %{ $opts // {} } }; $type = "${type}";

   $opts->{selected} //= NUL;
   $opts->{selected} = $opts->{selected} =~ m{ \A $type \z }imx ? TRUE : FALSE;

   return [ "${type}", $type, $opts ];
};

# Public methods
sub find_certification_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'certification' );
}

sub find_course_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'course' );
}

sub find_event_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'event' );
}

sub find_package_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'package' );
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

sub find_vehicle_model_by {
   return $_[ 0 ]->$_find_by( $_[ 1 ], 'vehicle_model' );
}

sub list_types {
   my ($self, $opts) = @_; $opts = { %{ $opts // {} } };

   my $fields = delete $opts->{fields};
   my $types = $self->search( { type_class => delete $opts->{type} },
                              { columns => [ 'id', 'name' ], %{ $opts } } );

   return [ map { $_type_tuple->( $_, $fields ) } $types->all ];
}

sub search_for_all_types {
   my ($self, $opts) = @_; $opts //= {};

   $opts->{order_by} //= [ 'type_class', 'name' ];

   return $self->search
      ( {}, { columns => [ 'name', 'type_class' ], %{ $opts } } );
}

sub search_for_call_categories {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'call_category' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub search_for_certification_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'certification' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub search_for_course_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'course' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub search_for_event_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'event' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub search_for_package_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'package' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub search_for_role_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'role' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub search_for_rota_types {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'rota' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub search_for_types {
   my ($self, $type_class, $opts) = @_; $opts //= {};

   $opts->{order_by} //= [ 'type_class', 'name' ];

   return $self->search
      ( { type_class => $type_class },
        { columns    => [ 'id', 'name', 'type_class' ], %{ $opts } } );
}

sub search_for_vehicle_models {
   my ($self, $opts) = @_; $opts //= {};

   return $self->search( { type_class => 'vehicle_model' },
                         { columns    => [ 'id', 'name' ], %{ $opts } } );
}

sub search_for_vehicle_types {
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

Copyright (c) 2017 Peter Flanigan. All rights reserved

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
