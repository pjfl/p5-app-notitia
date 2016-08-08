package App::Notitia::Model::Report;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form p_row p_table );
use App::Notitia::Util      qw( locm now_dt to_dt register_action_paths );
use Class::Usul::Functions  qw( sum throw );
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

# Private functions
my $_compare_counts = sub {
   my ($data, $k1, $k2) = @_;

   return $data->{ $k2 }->{count}->[ 4 ] <=> $data->{ $k1 }->{count}->[ 4 ];
};

my $_people_headers = sub {
   return [ map { { value => locm $_[ 0 ], "people_report_heading_${_}" } }
            0 .. 5 ];
};

my $_people_row = sub {
   my ($data, $k) = @_; my $rec = $data->{ $k }; my $counts = $rec->{count};

   return [ { value => $rec->{person}->label },
            { class => 'align-right', value => $counts->[ 0 ] // 0 },
            { class => 'align-right', value => $counts->[ 1 ] // 0 },
            { class => 'align-right', value => $counts->[ 2 ] // 0 },
            { class => 'align-right', value => $counts->[ 3 ] // 0 },
            { class => 'align-right', value => $counts->[ 4 ] // 0 } ];
};

my $_sum_counts = sub {
   my ($data, $k) = @_; my $counts = $data->{ $k }->{count};

   $counts->[ 4 ] = sum map { defined $_ ? $_ : 0 } @{ $counts };

   return $k;
};

# Private methods
my $_counts_by_person = sub {
   my ($self, $opts) = @_;

   my $slot_rs = $self->schema->resultset( 'Slot' );
   my $participent_rs = $self->schema->resultset( 'Participent' );
   my $attendees = $participent_rs->search_for_attendees( $opts );
   my $data = {};

   for my $slot ($slot_rs->search_for_slots( $opts )->all) {
      my $person = $slot->operator;
      my $rec = $data->{ $person->shortcode } //= { person => $person };
      my $index;

      $slot->type_name->is_controller and $index = 0;
      $slot->type_name->is_rider and $index = 1;
      $slot->type_name->is_driver and $index = 2;
      defined $index or next;
      $rec->{count}->[ $index ] //= 0; $rec->{count}->[ $index ]++;
   }

   for my $person (map { $_->participent } $attendees->all) {
      my $rec = $data->{ $person->shortcode } //= { person => $person };

      $rec->{count}->[ 3 ] //= 0; $rec->{count}->[ 3 ]++;
   }

   return $data;
};

my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

# Public methods
sub people : Role(person_manager) {
   my ($self, $req) = @_;

   my $now = now_dt;
   my $rota_name = $req->uri_params->( 0, { optional => TRUE } ) // 'main';
   my $report_from = $req->uri_params->( 1, { optional => TRUE } )
      // $now->clone->subtract( months => 1 )->set_time_zone( 'local' )->ymd;
   my $report_to = $req->uri_params->( 2, { optional => TRUE } )
      // $now->clone->set_time_zone( 'local' )->ymd;
   my $data = $self->$_counts_by_person( {
      after => to_dt( $report_from )->subtract( days => 1 ),
      before => to_dt( $report_to ),
      rota_type => $self->$_find_rota_type( $rota_name )->id, } );
   my $page = {
      forms => [ blank_form ],
      selected => 'people_report',
      title => locm $req, 'people_report_title'
   };
   my $form = $page->{forms}->[ 0 ];
   my $table = p_table $form, { headers => $_people_headers->( $req ) };

   p_row $table, [ map   { $_people_row->( $data, $_ ) }
                   sort  { $_compare_counts->( $data, $a, $b ) }
                   map   { $_sum_counts->( $data, $_ ) }
                   keys %{ $data } ];

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
