package App::Notitia::Controller::Event;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'event';

sub dispatch_request {
   sub (GET  + /event-info/*          + ?*) { [ 'event/event_info',      @_ ] },
   sub (GET  + /event-summary/**      + ?*) { [ 'event/event_summary',   @_ ] },
   sub (GET  + /events                + ?*) { [ 'event/events',          @_ ] },
   sub (POST + /event/*   | /event    + ?*) { [ 'event/from_request',    @_ ] },
   sub (GET  + /event/*   | /event    + ?*) { [ 'event/event',           @_ ] },
   sub (GET  + /message-participants  + ?*) { [ 'event/message',         @_ ] },
   sub (GET  + /participate/*         + ?*) { [ 'event/participate',     @_ ] },
   sub (POST + /participants          + ?*) { [ 'event/from_request',    @_ ] },
   sub (POST + /participants/*        + ?*) { [ 'event/from_request',    @_ ] },
   sub (GET  + /participants/**       + ?*) { [ 'event/participants',    @_ ] },
   sub (POST + /press-gang/*          + ?*) { [ 'event/from_request',    @_ ] },
   sub (GET  + /press-gang/*          + ?*) { [ 'event/press_gang',      @_ ] },
   sub (GET  + /vehicle-event-info/*  + ?*) { [ 'event/vehicle_info',    @_ ] },
   sub (POST + /vehicle-event/**      + ?*) { [ 'event/from_request',    @_ ] },
   sub (POST + /vehicle-event/*       + ?*) { [ 'event/from_request',    @_ ] },
   sub (GET  + /vehicle-event/**      + ?*) { [ 'event/vehicle_event',   @_ ] },
   sub (GET  + /vehicle-event/*       + ?*) { [ 'event/vehicle_event',   @_ ] },
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Controller::Event - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Controller::Event;
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
