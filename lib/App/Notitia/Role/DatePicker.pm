package App::Notitia::Role::DatePicker;

use namespace::autoclean;

use App::Notitia::Constants qw( FALSE NUL SPC TRUE );
use App::Notitia::DOM       qw( p_js );
use App::Notitia::Util      qw( js_submit_config to_dt );
use Moo::Role;

requires qw( add_csrf_token );

sub date_picker {
   my ($self, $req, $class, $rota_name, $local_dt, $href) = @_;

   my $form       =  {
      class       => $class,
      content     => {
         list     => [ {
            name  => 'rota_name',
            type  => 'hidden',
            value => $rota_name,
         }, {
            class => 'rota-date-field shadow submit',
            label => NUL,
            name  => 'rota_date',
            type  => 'date',
            value => $local_dt->ymd,
         }, {
            class => 'rota-date-field',
            disabled => TRUE,
            name  => 'rota_date_display',
            label => NUL,
            type  => 'textfield',
            value => $local_dt->day_abbr.SPC.$local_dt->day,
         }, ],
         type     => 'list', },
      form_name   => 'day-selector',
      href        => $href,
      type        => 'form', };

   $self->add_csrf_token( $req, $form );

   return $form;
}

sub date_picker_js {
   my ($self, $page, $action) = @_;

   $action //= 'day_selector'; my $args = [ $action, 'day-selector' ];

   p_js $page, js_submit_config 'rota_date', 'change', 'submitForm', $args;

   return;
}

sub date_picker_redirect {
   my ($self, $req, $actionp) = @_;

   my $rota_name = $req->body_params->( 'rota_name' );
   my $rota_date = $req->body_params->( 'rota_date' );
   my $args      = [ $rota_name, to_dt( $rota_date, 'local' )->ymd ];
   my $mid       = $req->query_params->( 'mid', { optional => TRUE } );
   my $params    = $mid ? { mid => $mid } : {};
   my $location  = $req->uri_for_action( $actionp, $args, $params );

   return { redirect => { location => $location } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::DatePicker - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::DatePicker;
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
