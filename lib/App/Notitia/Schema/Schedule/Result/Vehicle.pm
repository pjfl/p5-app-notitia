package App::Notitia::Schema::Schedule::Result::Vehicle;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string },
             '+'  => sub { $_[ 0 ]->_as_number }, fallback => 1;
use parent   'App::Notitia::Schema::Schedule::Base::Result';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE
                                SPC TRUE VARCHAR_MAX_SIZE );
use App::Notitia::DataTypes qw( date_data_type foreign_key_data_type
                                nullable_foreign_key_data_type
                                serial_data_type varchar_data_type );
use App::Notitia::Util      qw( now_dt );
use Class::Usul::Functions  qw( is_member throw );
use Try::Tiny;
use Unexpected::Functions   qw( VehicleAssigned );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'vehicle' );

$class->add_columns
   ( id       => serial_data_type,
     type_id  => foreign_key_data_type,
     model_id => nullable_foreign_key_data_type,
     owner_id => nullable_foreign_key_data_type,
     aquired  => date_data_type,
     disposed => date_data_type,
     colour   => varchar_data_type( 16 ),
     vrn      => varchar_data_type( 16 ),
     name     => varchar_data_type( 64 ),
     notes    => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'vrn' ] );

$class->belongs_to( model => "${result}::Type", 'model_id', $left_join );
$class->belongs_to( owner => "${result}::Person", 'owner_id', $left_join );
$class->belongs_to( type  => "${result}::Type", 'type_id' );

$class->has_many( histories => "${result}::VehicleHistory", 'vehicle_id' );

# Private functions
my $_display_vrn = sub {
   my $vrn = shift;

   $vrn =~ s{ \A ([A-Z]+ \d+) ([A-Z]+) \z }{$1 $2}mx;

   return $vrn;
};

my $_random_colour = sub {
   return sprintf '#%x%x%x', int rand 256, int rand 256, int rand 256;
};

# Private methods
sub _as_number {
   return $_[ 0 ]->id;
}

sub _as_string {
   return $_[ 0 ]->vrn;
}

my $_assert_public_or_private = sub {
   my $self = shift;

   $self->name and $self->owner_id
      and throw 'Cannot set name and owner', level => 2;

   return;
};

my $_assert_not_assigned_to_event = sub {
   my ($self, $rota_dt, $shift_t) = @_;

   my ($shift_start, $shift_end) = $self->shift_times( $rota_dt, $shift_t );
   my $tport_rs = $self->result_source->schema->resultset( 'Transport' );
   my $opts = { on => $rota_dt, vehicle => $self->vrn };

   for my $tport ($tport_rs->search_for_assigned_vehicles( $opts )->all) {
      my ($event_start, $event_end) = $tport->event->duration;

      $shift_end <= $event_start and next; $event_end <= $shift_start and next;

      throw VehicleAssigned, [ $self, $tport->event, 'event' ], level => 2;
   }

   return;
};

my $_assert_not_assigned_to_vehicle_event = sub {
   my ($self, $rota_dt, $shift_t) = @_;

   my ($shift_start, $shift_end) = $self->shift_times( $rota_dt, $shift_t );
   my $event_rs = $self->result_source->schema->resultset( 'Event' );
   my $opts = { on => $rota_dt, vehicle => $self->vrn, };

   for my $event ($event_rs->search_for_vehicle_events( $opts )->all) {
      my ($event_start, $event_end) = $event->duration;

      $shift_end <= $event_start and next; $event_end <= $shift_start and next;

      throw VehicleAssigned, [ $self, $event, 'vehicle event' ], level => 2;
   }

   return;
};

my $_find_assigner = sub {
   my ($self, $scode) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Person' )->find_by_shortcode( $scode );
};

my $_find_rota_type = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_rota_by( $name );
};

my $_find_slot = sub {
   my ($self, $rota_name, $rota_dt, $shift_t, $slot_t, $subslot) = @_;

   my $shift = $self->find_shift( $rota_name, $rota_dt, $shift_t );
   my $slot  = $self->find_slot( $shift, $slot_t, $subslot );

   $slot or throw 'Slot [_1] has not been claimed', [ $slot ];

   return $slot;
};

my $_assert_not_assigned_to_slot = sub {
   my ($self, $rota_name, $rota_dt, $shift_t) = @_;

   my $type_id  = $self->$_find_rota_type( $rota_name )->id;
   my $slots_rs = $self->result_source->schema->resultset( 'Slot' );
   my $slots    = $slots_rs->assignment_slots( $type_id, $rota_dt );

   for my $slot (grep { $_->type_name->is_rider } $slots->all) {
      $slot->get_column( 'shift_type' ) eq $shift_t
         and $slot->get_column( 'vehicle_name' )
         and $slot->get_column( 'vehicle_vrn'  ) eq $self->vrn
         and throw VehicleAssigned, [ $self, 'slot', $slot->subslot ],
                   level => 2;
   }

   return;
};

my $_assert_event_assignment_allowed = sub {
   my ($self, $event, $person) = @_;

   $person->assert_member_of( 'rota_manager' );

   my $opts = { on => $event->start_date, vehicle => $self->vrn };

   $self->assert_not_assigned_to_event( $event, $opts );
   $self->assert_not_assigned_to_slot( $event, $opts );
   $self->assert_not_assigned_to_vehicle_event( $event, $opts );
   return;
};

my $_assert_vehicle_model_allowed = sub {
   my ($self, $person) = @_; $self->model_id or return;

   is_member $self->model_id,
      [ map { $_->type->id } @{ $person->list_certifications } ]
         or throw '[_1] not certified for [_2]',
         [ $person->label, $self->model->label ];

   return;
};

my $_assert_slot_assignment_allowed = sub {
   my ($self, $rota_name, $rota_dt, $shift_t, $slot_t, $slot, $person) = @_;

   $person->assert_member_of( 'rota_manager' );

   if ($slot_t eq 'rider' and $slot->bike_requested) {
      $self->type ne 'bike' and
         throw 'Vehicle [_1] is not a bike and one was requested', [ $self ];

      $self->name or throw 'Vehicle [_1] is not a service vehicle', [ $self ];
   }

   $self->$_assert_vehicle_model_allowed( $slot->operator );
   $self->$_assert_not_assigned_to_event( $rota_dt, $shift_t );
   $self->$_assert_not_assigned_to_slot( $rota_name, $rota_dt, $shift_t );
   $self->$_assert_not_assigned_to_vehicle_event( $rota_dt, $shift_t );
   return;
};

# Public methods
sub assign_private {
   my ($self, $rota_name, $date, $shift_type, $slot_type, $subslot) = @_;

   my $slot = $self->$_find_slot
      ( $rota_name, $date, $shift_type, $slot_type, $subslot );

   $slot->operator_vehicle_id( $self->id );

   return $slot->update;
}

sub assign_to_event {
   my ($self, $event_uri, $assigner_name, $provisional) = @_;

   my $schema   = $self->result_source->schema;
   my $event    = $schema->resultset( 'Event' )->find_event_by( $event_uri );
   my $assigner = $self->$_find_assigner( $assigner_name );

   $self->$_assert_event_assignment_allowed( $event, $assigner );

   return $schema->resultset( 'Transport' )->create( {
      event_id            => $event->id,
      vehicle_id          => $self->id,
      vehicle_assigner_id => $assigner->id,
      provisional         => $provisional,
      provisional_created => now_dt,
   } );
}

sub assign_slot {
   my ($self, $rota_name, $rota_dt, $slot_name, $assigner, $provisional) = @_;

   my ($shift_t, $slot_t, $subslot) = split m{ _ }mx, $slot_name, 3;

   my $slot   = $self->$_find_slot
      ( $rota_name, $rota_dt, $shift_t, $slot_t, $subslot );
   my $person = $self->$_find_assigner( $assigner );

   $self->$_assert_slot_assignment_allowed
      ( $rota_name, $rota_dt, $shift_t, $slot_t, $slot, $person );

   $slot->vehicle_id( $self->id );
   $slot->vehicle_assigner_id( $person->id );
   $slot->provisional( $provisional );
   $slot->provisional_created( now_dt );
   return $slot->update;
}

sub insert {
   my $self = shift; my $columns = { $self->get_inflated_columns };

   $columns->{colour} or $columns->{colour} = $_random_colour->();

   $self->set_inflated_columns( $columns );

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   $self->$_assert_public_or_private();

   return $self->next::method;
}

sub is_event_assignment_allowed {
   my ($self, $event_uri, $assigner_name) = @_;

   my $schema   = $self->result_source->schema;
   my $event    = $schema->resultset( 'Event' )->find_event_by( $event_uri );
   my $assigner = $self->$_find_assigner( $assigner_name );
   my $allowed  = TRUE;

   try   { $self->$_assert_event_assignment_allowed( $event, $assigner ) }
   catch { $allowed = FALSE };

   return $allowed;
}

sub is_slot_assignment_allowed {
   my ($self, $rota_name, $rota_dt, $slot_name, $assigner) = @_;

   my ($shift_t, $slot_t, $subslot) = split m{ _ }mx, $slot_name, 3;

   my $slot = $self->$_find_slot
      ( $rota_name, $rota_dt, $shift_t, $slot_t, $subslot );
   my $person = $self->$_find_assigner( $assigner );
   my $allowed = TRUE;

   try   {
      $self->$_assert_slot_assignment_allowed
         ( $rota_name, $rota_dt, $shift_t, $slot_t, $slot, $person );
   }
   catch { $allowed = FALSE };

   return $allowed;
}

sub label {
   my $self = shift; my $vrn = $self->vrn;

   return $self->name  ? $_display_vrn->( $vrn ).' ('.$self->name.')'
        : $self->owner ? $_display_vrn->( $vrn ).' ('.$self->owner->label.')'
                       : $_display_vrn->( $vrn );
}

sub slotref {
   return $_[ 0 ]->name ? $_[ 0 ]->name : $_[ 0 ]->vrn;
}

sub unassign_private {
   my ($self, $rota_name, $date, $shift_type, $slot_type, $subslot) = @_;

   my $slot = $self->$_find_slot
      ( $rota_name, $date, $shift_type, $slot_type, $subslot );

   $slot->operator_vehicle_id( undef );

   return $slot->update;
}

sub unassign_from_event {
   my ($self, $event_uri, $assigner_name) = @_;

   my $schema    = $self->result_source->schema;
   my $event     = $schema->resultset( 'Event' )->find_event_by( $event_uri );
   my $tport_rs  = $schema->resultset( 'Transport' );
   my $transport = $tport_rs->find( $event->id, $self->id );

   return $transport->delete;
}

sub unassign_slot {
   my ($self, $rota_name, $date, $slot_name, $unassigner) = @_;

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $slot_name, 3;

   my $slot = $self->$_find_slot
      ( $rota_name, $date, $shift_type, $slot_type, $subslot );

   return $slot->unassign_vehicle;
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $columns = { $self->get_inflated_columns };

   $columns->{colour} or $columns->{colour} = $_random_colour->();

   $self->set_inflated_columns( $columns ); $self->validate( TRUE );

   $self->$_assert_public_or_private();

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints    => {
         colour      => { max_length => 16, min_length => 3, },
         name        => { max_length => 64, min_length => 3, },
         notes       => { max_length => VARCHAR_MAX_SIZE(), min_length => 0 },
         vrn         => { max_length => 16, min_length => 3, },
      },
      fields         => {
         aquired     => { validate => 'isValidDate' },
         colour      => { validate => 'isValidLength' },
         disposed    => { validate => 'isValidDate' },
         name        => { validate => 'isValidLength isValidIdentifier' },
         notes       => { validate => 'isValidLength isValidText' },
         vrn         => {
            unique   => TRUE,
            filters  => 'filterWhiteSpace filterUpperCase',
            validate => 'isMandatory isValidLength isValidIdentifier' },
      },
      level => 8,
   };
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
