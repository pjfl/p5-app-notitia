package App::Notitia::Schema::Schedule::Result::Type;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string },
             '+'  => sub { $_[ 0 ]->_as_number }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( FALSE TRUE TYPE_CLASS_ENUM );
use App::Notitia::Util      qw( enumerated_data_type serial_data_type
                                varchar_data_type );
use Class::Usul::Functions  qw( throw );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'type' );

$class->add_columns
   ( id         => serial_data_type,
     name       => varchar_data_type( 32 ),
     type_class => enumerated_data_type( TYPE_CLASS_ENUM ), );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'name', 'type_class' ] );

$class->has_many( slot_certs => "${result}::SlotCriteria",
                  'certification_type_id' );

# Private methods
sub _as_number {
   return $_[ 0 ]->id;
}

sub _as_string {
   return $_[ 0 ]->name;
}

# Public methods
sub add_cert_type_to {
   my ($self, $slot_type) = @_;

   $self->is_cert_type_member_of( $slot_type )
      and throw 'Cert. [_1] already required by slot type [_2]',
          [ $self, $slot_type ];

   return $self->create_related( 'slot_certs', { slot_type => $slot_type } );
}

sub assert_cert_type_member_of {
   my ($self, $slot_type) = @_;

   my $slot_role = $self->slot_certs->find( $slot_type, $self->id );

   defined $slot_role
      or throw 'Cert. [_1] is not required by slot type [_2]',
               [ $self, $slot_type ], level => 2;

   return $slot_role;
}

sub delete_cert_type_from {
   return $_[ 0 ]->assert_cert_type_member_of( $_[ 1 ] )->delete;
}

sub is_cert_type_member_of {
   my ($self, $slot_type) = @_;

   return $slot_type && $self->slot_certs->find( $slot_type, $self->id )
        ? TRUE : FALSE;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Type - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Type;
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
