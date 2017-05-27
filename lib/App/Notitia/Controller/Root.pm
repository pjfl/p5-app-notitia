package App::Notitia::Controller::Root;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'z_root'; # Must sort to last place

sub dispatch_request {
   sub (GET  + /about                     + ?*) {[ 'user/about',          @_ ]},
   sub (GET  + /activity                  + ?*) {[ 'user/activity',       @_ ]},
   sub (GET  + /changes                   + ?*) {[ 'user/changes',        @_ ]},
   sub (GET  + /check-field               + ?*) {[ 'user/check_field',    @_ ]},
   sub (GET  + /show-if-needed            + ?*) {[ 'user/show_if_needed', @_ ]},
   sub (POST + /user/email-subscription/* + ?*) {[ 'user/from_request',   @_ ]},
   sub (GET  + /user/email-subscription/* + ?*) {[ 'user/email_subs',     @_ ]},
   sub (GET  + /user/email-subscription   + ?*) {[ 'user/email_subs',     @_ ]},
   sub (POST + /user/login                + ?*) {[ 'user/from_request',   @_ ]},
   sub (GET  + /user/login                + ?*) {[ 'user/login',          @_ ]},
   sub (POST + /user/logout               + ?*) {[ 'user/logout_action',  @_ ]},
   sub (GET  + /user/password/*           + ?*) {[ 'user/change_password',@_ ]},
   sub (POST + /user/password             + ?*) {[ 'user/from_request',   @_ ]},
   sub (GET  + /user/password             + ?*) {[ 'user/change_password',@_ ]},
   sub (POST + /user/profile              + ?*) {[ 'user/from_request',   @_ ]},
   sub (GET  + /user/profile              + ?*) {[ 'user/profile',        @_ ]},
   sub (GET  + /user/reset/*              + ?*) {[ 'user/reset_password', @_ ]},
   sub (POST + /user/reset                + ?*) {[ 'user/from_request',   @_ ]},
   sub (GET  + /user/reset                + ?*) {[ 'user/request_reset',  @_ ]},
   sub (POST + /user/sms-subscription/*   + ?*) {[ 'user/from_request',   @_ ]},
   sub (GET  + /user/sms-subscription/*   + ?*) {[ 'user/sms_subs',       @_ ]},
   sub (GET  + /user/sms-subscription     + ?*) {[ 'user/sms_subs',       @_ ]},
   sub (GET  + /user/totp-request         + ?*) {[ 'user/totp_request',   @_ ]},
   sub (GET  + /user/totp-secret/*        + ?*) {[ 'user/totp_secret',    @_ ]},
   sub (GET  + /user/totp-secret          + ?*) {[ 'user/totp_secret',    @_ ]},
   sub (GET  + /index | /                 + ?*) {[ 'docs/index',          @_ ]},
   sub (GET  + /**                        + ?*) {[ 'docs/not_found',      @_ ]},
   sub (DELETE                            + ?*) {[ 'docs/not_found',      @_ ]},
   sub (POST                              + ?*) {[ 'docs/not_found',      @_ ]},
   sub (PUT                               + ?*) {[ 'docs/not_found',      @_ ]},
   sub (GET                               + ?*) {[ 'docs/index',          @_ ]};
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Controller::Root - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Controller::Root;
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
