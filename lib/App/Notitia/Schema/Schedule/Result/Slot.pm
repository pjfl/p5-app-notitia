package App::Notitia::Schema::Schedule::Result::Slot;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( FALSE SLOT_TYPE_ENUM );
use App::Notitia::Util      qw( bool_data_type enumerated_data_type
                                foreign_key_data_type
                                nullable_foreign_key_data_type
                                numerical_id_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'slot' );

$class->add_columns
   ( shift_id            => foreign_key_data_type,
     operator_id         => foreign_key_data_type,
     type_class          => enumerated_data_type( SLOT_TYPE_ENUM, 0 ),
     subslot             => numerical_id_data_type,
     bike_requested      => bool_data_type,
     vehicle_assigner_id => nullable_foreign_key_data_type,
     vehicle_id          => nullable_foreign_key_data_type, );

$class->set_primary_key( 'shift_id', 'type_class', 'subslot' );

$class->belongs_to( shift    => "${result}::Shift",   'shift_id' );
$class->belongs_to( operator => "${result}::Person",  'operator_id' );
$class->belongs_to( vehicle  => "${result}::Vehicle", 'vehicle_id', $left_join);
$class->belongs_to( vehicle_assigner => "${result}::Person",
                    'vehicle_assigner_id', $left_join );

$class->has_many  ( personal_vehicles => "${result}::Vehicle",
                    { 'foreign.owner_id' => 'self.operator_id' } );

# Private methods
sub _as_string {
   my $self = shift; my $shift = $self->shift; my $rota = $shift->rota;

   return $rota->type.'_'.$rota->date->dmy.'_'.$shift.'_'
        . $self->type_class.'_'.$self->subslot;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Slot - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Slot;
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
