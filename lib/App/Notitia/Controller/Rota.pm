package App::Notitia::Controller::Rota;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'rota';

sub dispatch_request {
   sub (GET  + /allocation-key/*     + ?*) { [ 'week/alloc_key',       @_ ] },
   sub (GET  + /allocation-table/**  + ?*) { [ 'week/alloc_table',     @_ ] },
   sub (GET  + /assignment-summary/* + ?*) { [ 'month/assign_summary', @_ ] },
   sub (POST + /day-rota             + ?*) { [ 'day/from_request',     @_ ] },
   sub (GET  + /day-rota/**          + ?*) { [ 'day/day_rota',         @_ ] },
   sub (GET  + /day-rota             + ?*) { [ 'day/day_rota',         @_ ] },
   sub (GET  + /events-summary/*     + ?*) { [ 'month/events_summary', @_ ] },
   sub (GET  + /month-rota/**        + ?*) { [ 'month/month_rota',     @_ ] },
   sub (GET  + /month-rota           + ?*) { [ 'month/month_rota',     @_ ] },
   sub (POST + /operator-vehicle/**  + ?*) { [ 'day/from_request',     @_ ] },
   sub (GET  + /operator-vehicle/**  + ?*) { [ 'day/operator_vehicle', @_ ] },
   sub (POST + /slot/**              + ?*) { [ 'day/from_request',     @_ ] },
   sub (GET  + /slot/**              + ?*) { [ 'day/slot',             @_ ] },
   sub (GET  + /user-slots/**        + ?*) { [ 'month/user_slots',     @_ ] },
   sub (GET  + /vehicle-allocation/**+ ?*) { [ 'week/allocation',      @_ ] },
   sub (POST + /vehicle-allocation/**+ ?*) { [ 'week/from_request',    @_ ] },
   sub (GET  + /week-rota/**         + ?*) { [ 'week/week_rota',       @_ ] };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Controller::Rota - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Controller::Rota;
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
