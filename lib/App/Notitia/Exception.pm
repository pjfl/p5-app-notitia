package App::Notitia::Exception;

use namespace::autoclean;

use Unexpected::Functions qw( has_exception );
use Moo;

extends q(Class::Usul::Exception);

my $class = __PACKAGE__;

has_exception $class              => parents => [ 'Class::Usul::Exception' ];

has_exception 'Authentication'    => parents => [ $class ];

has_exception 'AccountInactive'   => parents => [ 'Authentication' ],
   error   => 'User [_1] authentication failed';

has_exception 'IncorrectPassword' => parents => [ 'Authentication' ],
   error   => 'User [_1] authentication failed';

has_exception 'PasswordExpired'   => parents => [ 'Authentication' ],
   error   => 'User [_1] authentication failed';

has_exception 'SlotFree'          => parents => [ $class ],
   error   => 'Slot [_1] is free';

has_exception 'SlotTaken'         => parents => [ $class ],
   error   => 'Slot [_1] alredy taken by [_2]';

has_exception 'URINotFound'       => parents => [ $class ],
   error   => 'URI [_1] not found';

has '+class' => default => $class;

sub code {
   return $_[ 0 ]->rv;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Exception - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Exception;
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
