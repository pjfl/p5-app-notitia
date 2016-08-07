package App::Notitia::Model::Report;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form );
use App::Notitia::Util      qw( locm now_dt to_dt register_action_paths );
use Class::Usul::Functions  qw( throw );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'report';

register_action_paths
   'report/people' => 'people-report',
   'report/slots' => 'slots-report',
   'report/vehicles' => 'vehicles-report';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private methods
my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

# Public methods
sub people : Role(person_manager) {
   my ($self, $req) = @_;

   my $now = now_dt;
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $report_from = $req->uri_params->( 1, { optional => TRUE } )
      // $now->subtract( months => 1 )->set_time_zone( 'local' )->ymd;
   my $report_to = $req->uri_params->( 2, { optional => TRUE } )
      // $now->set_time_zone( 'local' )->ymd;
   my $opts = { after => to_dt( $report_from )->subtract( days => 1 ),
                before => to_dt( $report_to ),
                page => $req->query_params->( { optional => TRUE } ) // 1,
                rota_type => $self->$_find_rota_type( $rota_name )->id,
                rows => $req->session->rows_per_page, };
   my $slots = $self->schema->resultset( 'Slot' )->search_for_slots( $opts );
   my $page = {
      forms => [ blank_form ],
      selected => 'people_report',
      title => locm $req, 'people_report_heading'
   };
   my $form = $page->{forms}->[ 0 ];

   return $self->get_stash( $req, $page );
}

sub slots : Role(rota_manager) {
   my ($self, $req) = @_;

   my $page = {
      selected => 'slots_report',
      title => locm $req, 'slots_report_heading'
   };

   return $self->get_stash( $req, $page );
}

sub vehicles : Role(rota_manager) {
   my ($self, $req) = @_;

   my $page = {
      selected => 'vehicles_report',
      title => locm $req, 'vehicles_report_heading'
   };

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Report - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Report;
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
