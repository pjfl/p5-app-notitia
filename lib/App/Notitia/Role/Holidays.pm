package App::Notitia::Role::Holidays;

use namespace::autoclean;

use Class::Usul::Constants qw( FALSE TRUE );
use Moo::Role;

requires qw( plugins );

# Public methods
sub bank_holidays {
   my ($self, $dt) = @_;

   return exists $self->plugins->{holidays}
        ? $self->plugins->{holidays}->bank_holidays( $dt )
        : [];
}

sub is_bank_holiday {
   my ($self, $dt) = @_;

   return exists $self->plugins->{holidays}
        ? $self->plugins->{holidays}->is_bank_holiday( $dt )
        : FALSE;
}

sub is_working_day {
   my ($self, $dt) = @_;

   return exists $self->plugins->{holidays}
        ? $self->plugins->{holidays}->is_working_day( $dt )
        : $dt->day_of_week > 5 ? FALSE : TRUE;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::Holidays - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::Holidays;
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
