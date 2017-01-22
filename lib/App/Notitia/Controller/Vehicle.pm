package App::Notitia::Controller::Vehicle;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'vehicle';

sub dispatch_request {
   sub (GET  + /vehicles              + ?*) { [ 'asset/vehicles',        @_ ] },
   sub (GET  + /vehicle-assign/**     + ?*) { [ 'asset/assign',          @_ ] },
   sub (GET  + /vehicle-events/*      + ?*) { [ 'asset/vehicle_events',  @_ ] },
   sub (GET  + /vehicle-request-info/*+ ?*) { [ 'asset/request_info',    @_ ] },
   sub (GET  + /vehicle-request/*     + ?*) { [ 'asset/request_vehicle', @_ ] },
   sub (POST + /vehicle/**            + ?*) { [ 'asset/from_request',    @_ ] },
   sub (POST + /vehicle/*             + ?*) { [ 'asset/from_request',    @_ ] },
   sub (POST + /vehicle               + ?*) { [ 'asset/from_request',    @_ ] },
   sub (GET  + /vehicle/*             + ?*) { [ 'asset/vehicle',         @_ ] },
   sub (GET  + /vehicle               + ?*) { [ 'asset/vehicle',         @_ ] },
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Controller::Vehicle - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Controller::Vehicle;
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
