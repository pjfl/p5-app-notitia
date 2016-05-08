package App::Notitia::Schema::Schedule::ResultSet::Transport;

use strictures;
use parent 'DBIx::Class::ResultSet';

sub assigned_vehicle_count {
   return $_[ 0 ]->count( { event_id => $_[ 1 ] } );
}

sub search_for_assigned_vehicles {
   my ($self, $opts) = @_; $opts = { %{ $opts } };

   my $where  = { 'vehicle.vrn' => delete $opts->{vehicle} };
   my $parser = $self->result_source->schema->datetime_parser;

   if (my $after = delete $opts->{after}) {
      $where->{ 'start_rota.date' } =
              { '>' => $parser->format_datetime( $after ) };
      $opts->{order_by} //= 'date';
   }

   if (my $before = delete $opts->{before}) {
      $where->{ 'start_rota.date' } =
              { '<' => $parser->format_datetime( $before ) };
   }

   if (my $ondate = delete $opts->{on}) {
      $where->{ 'start_rota.date' } = $parser->format_datetime( $ondate );
   }

   $opts->{order_by} //= { -desc => 'date' }; delete $opts->{event_type};

   my $prefetch = delete $opts->{prefetch}
               // [ { 'event' => 'start_rota' }, 'vehicle' ];

   return $self->search( $where, { prefetch => $prefetch, %{ $opts } } );
}

sub search_for_vehicle_by_type {
   my ($self, $event_id, $vehicle_type_id) = @_;

   return $self->search
      ( { event_id => $event_id, 'vehicle.type_id' => $vehicle_type_id },
        { prefetch => 'vehicle' } );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Transport - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Transport;
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
