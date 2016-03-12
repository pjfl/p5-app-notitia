package App::Notitia::Schema::Schedule::ResultSet::Slot;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );

# Public methods
sub find_slot_by {
   my ($self, $shift, $slot_type, $subslot) = @_;

   return $self->find( { shift_id => $shift->id, type_class => $slot_type,
                         subslot  => $subslot } );
}

sub list_slots_for {
   my ($self, $type_id, $date) = @_;

   return $self->search
      ( { 'rota.type_id' => $type_id, 'rota.date' => $date },
        { columns  => [ qw( bike_requested operator.name
                            type_class vehicle.name subslot ) ],
          join     => [ { 'shift' => 'rota' }, 'operator', 'vehicle', ],
          prefetch => [ { 'shift' => 'rota' }, 'operator', 'vehicle',
                        'personal_vehicles' ] } );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Slot - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Slot;
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
