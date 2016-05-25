package App::Notitia::Schema::Schedule::ResultSet::VehicleRequest;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( FALSE TRUE );
use Class::Usul::Functions  qw( is_member );

sub search_for_events_with_unassigned_vreqs {
   my ($self, $opts) = @_; my @tuples; $opts = { %{ $opts } };

   my $where  = { 'quantity' => { '>' => 0 } };
   my $parser = $self->result_source->schema->datetime_parser;

   if (my $ondate = delete $opts->{on}) {
      $where->{ 'start_rota.date' } = $parser->format_datetime( $ondate );
   }

   my $prefetch = [ { 'event' => 'start_rota' } ];
   my $tport_rs = $self->result_source->schema->resultset( 'Transport' );

   for my $vreq ($self->search( $where, { prefetch => $prefetch } )->all) {
      my $where    = { 'event.id'        => $vreq->event_id,
                       'vehicle.type_id' => $vreq->type_id };
      my $prefetch = [ 'event', 'vehicle' ];
      my $count    = $tport_rs->count( $where, { prefetch => $prefetch } );

      $vreq->quantity > $count
         and not is_member $vreq->event->id, [ map { $_->[ 0 ] } @tuples ]
         and push @tuples, [ $vreq->event->id, $vreq->event ];
   }

   return map { $_->[ 1 ] } @tuples;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::VehicleRequest - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::VehicleRequest;
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
