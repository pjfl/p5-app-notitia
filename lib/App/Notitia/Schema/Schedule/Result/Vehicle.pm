package App::Notitia::Schema::Schedule::Result::Vehicle;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Util     qw( date_data_type foreign_key_data_type
                               nullable_foreign_key_data_type
                               serial_data_type varchar_data_type );
use Class::Usul::Functions qw( throw );
use Scalar::Util           qw( blessed );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'vehicle' );

$class->add_columns
   ( id       => serial_data_type,
     type_id  => foreign_key_data_type,
     owner_id => nullable_foreign_key_data_type,
     aquired  => date_data_type,
     disposed => date_data_type,
     vrn      => varchar_data_type( 16 ),
     name     => varchar_data_type( 64 ),
     notes    => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'vrn' ] );

$class->belongs_to( owner => "${result}::Person", 'owner_id', $left_join );
$class->belongs_to( type  => "${result}::Type", 'type_id' );

# Private methods
sub _as_string {
   return $_[ 0 ]->name ? $_[ 0 ]->name : $_[ 0 ]->vrn;
}

my $_assert_event_assignment_allowed = sub {
   my ($self, $event, $assigner) = @_;

   $assigner->assert_member_of( 'asset_manager' );

   my $schema     = $self->result_source->schema;
   my $dtp        = $schema->storage->datetime_parser;
   my $event_date = $dtp->format_datetime( $event->rota->date );
   my $event_rs   = $schema->resultset( 'Event' );
   my $rota_rs    = $schema->resultset( 'Rota'  );

   for my $rota ($rota_rs->search( { date => $event_date } )){
      for my $other ($event_rs->search( { rota_id  => $rota->id },
                                        { prefetch => 'transports' } )) {
         for my $transport ($other->transports) {
            $transport->vehicle_id != $self->id and next;

            $transport->event_id == $event->id
               and throw 'Vehicle [_1] already assigned to this event',
                         [ $self ], level => 2;
            # TODO: Test for overlapping times
            throw 'Vehicle [_1] already assigned to event [_2]',
                  [ $self, $event ], level => 2;
         }
      }
   }

   return;
};

my $_assert_slot_assignment_allowed = sub {
   my ($self, $assigner, $slot_type, $bike_requested) = @_;

   $assigner->assert_member_of( 'asset_manager' );

   $slot_type eq 'rider' and $bike_requested and $self->type ne 'bike'
      and throw 'Vehicle [_1] is not a bike and one was requested', [ $self ];

   return;
};

my $_find_assigner = sub {
   my ($self, $name) = @_;

   my $schema    = $self->result_source->schema;
   my $person_rs = $schema->resultset( 'Person' );
   my $assigner  = $person_rs->search( { name => $name } )->first
      or throw 'Person [_1] is unknown', [ $name ], level => 2;

   return $assigner;
};

# Public methods
sub assign_to_event {
   my ($self, $event_name, $assigner_name) = @_;

   my $schema   = $self->result_source->schema;
   my $event_rs = $schema->resultset( 'Event' );
   my $event    = $event_rs->search
      ( { name => $event_name }, { prefetch => 'rota' } )->first
      or throw 'Event [_1] is unknown', [ $event_name ];
   my $assigner = $self->$_find_assigner( $assigner_name );

   $self->$_assert_event_assignment_allowed( $event, $assigner );

   return $schema->resultset( 'Transport' )->create
      ( { event_id => $event->id, vehicle_id => $self->id,
          vehicle_assigner_id => $assigner->id } );
}

sub assign_to_slot {
   my ($self, $rota_name, $date, $shift_type, $slot_type, $subslot, $name) = @_;

   my $shift = $self->find_shift( $rota_name, $date, $shift_type );
   my $slot  = $self->find_slot( $shift, $slot_type, $subslot );

   $slot or throw 'Slot [_1] has not been claimed', [ $slot ];

   my $assigner = $self->$_find_assigner( $name );

   $self->$_assert_slot_assignment_allowed
      ( $assigner, $slot_type, $slot->bike_requested );

   $slot->vehicle_id( $self->id ); $slot->vehicle_assigner_id( $assigner->id );

   return $slot->update;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Vehicle - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Vehicle;
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
