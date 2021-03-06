package App::Notitia::Controller::Main;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'main';

sub dispatch_request {
   sub (GET  + /admin-index           + ?*) {[ 'admin/index',             @_ ]},
   sub (POST + /certifications/*      + ?*) {[ 'certs/from_request',      @_ ]},
   sub (GET  + /certifications/*      + ?*) {[ 'certs/certifications',    @_ ]},
   sub (POST + /certification/**      + ?*) {[ 'certs/from_request',      @_ ]},
   sub (GET  + /certification/**      + ?*) {[ 'certs/certification',     @_ ]},
   sub (GET  + /contacts              + ?*) {[ 'person/contacts',         @_ ]},
   sub (POST + /email-template/*      + ?*) {[ 'manage/from_request',     @_ ]},
   sub (POST + /email-template        + ?*) {[ 'manage/from_request',     @_ ]},
   sub (GET  + /email-template/*      + ?*) {[ 'manage/template_view',    @_ ]},
   sub (GET  + /email-template        + ?*) {[ 'manage/template_view',    @_ ]},
   sub (GET  + /email-templates       + ?*) {[ 'manage/template_list',    @_ ]},
   sub (GET  + /endorsements/*        + ?*) {[ 'blots/endorsements',      @_ ]},
   sub (POST + /endorsement/**        + ?*) {[ 'blots/from_request',      @_ ]},
   sub (GET  + /endorsement/**        + ?*) {[ 'blots/endorsement',       @_ ]},
   sub (POST + /event-control/**      + ?*) {[ 'admin/from_request',      @_ ]},
   sub (POST + /event-control         + ?*) {[ 'admin/from_request',      @_ ]},
   sub (GET  + /event-control/**      + ?*) {[ 'admin/event_control',     @_ ]},
   sub (GET  + /event-control         + ?*) {[ 'admin/event_control',     @_ ]},
   sub (POST + /event-controls/**     + ?*) {[ 'admin/from_request',      @_ ]},
   sub (POST + /event-controls        + ?*) {[ 'admin/from_request',      @_ ]},
   sub (GET  + /event-controls        + ?*) {[ 'admin/event_controls',    @_ ]},
   sub (POST + /jobdaemon-status      + ?*) {[ 'daemon/from_request',     @_ ]},
   sub (GET  + /jobdaemon-status      + ?*) {[ 'daemon/status',           @_ ]},
   sub (POST + /log/*                 + ?*) {[ 'admin/from_request',      @_ ]},
   sub (GET  + /log/*                 + ?*) {[ 'admin/logs',              @_ ]},
   sub (GET  + /management-dialog     + ?*) {[ 'manage/dialog',           @_ ]},
   sub (GET  + /management-index      + ?*) {[ 'manage/index',            @_ ]},
   sub (GET  + /message-people        + ?*) {[ 'person/message',          @_ ]},
   sub (GET  + /mugshot/*             + ?*) {[ 'person/mugshot',          @_ ]},
   sub (POST + /people                + ?*) {[ 'person/from_request',     @_ ]},
   sub (GET  + /people                + ?*) {[ 'person/people',           @_ ]},
   sub (GET  + /person-summary/*      + ?*) {[ 'person/person_summary',   @_ ]},
   sub (GET  + /person-activate/*     + ?*) {[ 'person/activate',         @_ ]},
   sub (POST + /person/* | /person    + ?*) {[ 'person/from_request',     @_ ]},
   sub (GET  + /person/* | /person    + ?*) {[ 'person/person',           @_ ]},
   sub (GET  + /personal-document/*   + ?*) {[ 'certs/upload_document',   @_ ]},
   sub (POST + /role/*                + ?*) {[ 'role/from_request',       @_ ]},
   sub (GET  + /role/*                + ?*) {[ 'role/role',               @_ ]},
   sub (POST + /slot-certs/*          + ?*) {[ 'admin/from_request',      @_ ]},
   sub (GET  + /slot-certs/*          + ?*) {[ 'admin/slot_certs',        @_ ]},
   sub (GET  + /slot-roles            + ?*) {[ 'admin/slot_roles',        @_ ]},
   sub (POST + /type/**               + ?*) {[ 'admin/from_request',      @_ ]},
   sub (GET  + /type/**  | /type/*    + ?*) {[ 'admin/type',              @_ ]},
   sub (GET  + /type-classes          + ?*) {[ 'admin/type_classes',      @_ ]},
   sub (GET  + /types                 + ?*) {[ 'admin/types',             @_ ]};
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Controller::Main - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Controller::Main;
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
