package App::Notitia::Controller::Call;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'call';

sub dispatch_request {
   sub (POST + /customer  | /customer/*   + ?*) {[ 'util/from_request',   @_ ]},
   sub (GET  + /customer  | /customer/*   + ?*) {[ 'util/customer',       @_ ]},
   sub (GET  + /customers                 + ?*) {[ 'util/customers',      @_ ]},
   sub (POST + /delivery/*/package/*      + ?*) {[ 'call/from_request',   @_ ]},
   sub (POST + /delivery/*/package        + ?*) {[ 'call/from_request',   @_ ]},
   sub (GET  + /delivery/*/package/*      + ?*) {[ 'call/package',        @_ ]},
   sub (GET  + /delivery/*/package        + ?*) {[ 'call/package',        @_ ]},
   sub (POST + /delivery/*/stage/*        + ?*) {[ 'call/from_request',   @_ ]},
   sub (POST + /delivery/*/stage          + ?*) {[ 'call/from_request',   @_ ]},
   sub (GET  + /delivery/*/stage/*        + ?*) {[ 'call/leg',            @_ ]},
   sub (GET  + /delivery/*/stage          + ?*) {[ 'call/leg',            @_ ]},
   sub (POST + /delivery  | /delivery/*   + ?*) {[ 'call/from_request',   @_ ]},
   sub (GET  + /delivery  | /delivery/*   + ?*) {[ 'call/journey',        @_ ]},
   sub (GET  + /delivery-stages/*         + ?*) {[ 'call/delivery_stages',@_ ]},
   sub (GET  + /deliveries                + ?*) {[ 'call/journeys',       @_ ]},
   sub (POST + /distances | /distances/** + ?*) {[ 'util/from_request',   @_ ]},
   sub (GET  + /distances | /distances/** + ?*) {[ 'util/distances',      @_ ]},
   sub (POST + /incident/*/parties        + ?*) {[ 'inc/from_request',    @_ ]},
   sub (GET  + /incident/*/parties        + ?*) {[ 'inc/incident_party',  @_ ]},
   sub (POST + /incident  | /incident/*   + ?*) {[ 'inc/from_request',    @_ ]},
   sub (GET  + /incident  | /incident/*   + ?*) {[ 'inc/incident',        @_ ]},
   sub (GET  + /incidents                 + ?*) {[ 'inc/incidents',       @_ ]},
   sub (POST + /location  | /location/*   + ?*) {[ 'util/from_request',   @_ ]},
   sub (GET  + /location  | /location/*   + ?*) {[ 'util/location',       @_ ]},
   sub (GET  + /locations                 + ?*) {[ 'util/locations',      @_ ]};
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Controller::Call - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Controller::Call;
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
