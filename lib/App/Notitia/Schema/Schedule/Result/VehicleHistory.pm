package App::Notitia::Schema::Schedule::Result::VehicleHistory;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string },
             '+'  => sub { $_[ 0 ]->_as_number }, fallback => 1;
use parent   'App::Notitia::Schema::Schedule::Base::Result';

use App::Notitia::Constants qw( SPC TRUE );
use App::Notitia::DataTypes qw( date_data_type foreign_key_data_type
                                serial_data_type unsigned_int_data_type );
use App::Notitia::Util      qw( local_dt month_label );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'vehicle_history' );

$class->add_columns
   ( id                 => serial_data_type,
     vehicle_id         => foreign_key_data_type,
     period_start       => date_data_type,
     last_fueled        => date_data_type,
     tax_due            => date_data_type,
     mot_due            => date_data_type,
     insurance_due      => date_data_type,
     next_service_due   => date_data_type,
     next_service_miles => unsigned_int_data_type( 0 ),
     current_miles      => unsigned_int_data_type( 0 ),
     front_tyre_miles   => unsigned_int_data_type( 0 ),
     front_tyre_life    => unsigned_int_data_type( 0 ),
     rear_tyre_miles    => unsigned_int_data_type( 0 ),
     rear_tyre_life     => unsigned_int_data_type( 0 ), );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'vehicle_id', 'period_start' ] );

$class->belongs_to( vehicle => "${result}::Vehicle", 'vehicle_id' );

# Private methods
sub _as_number {
   return $_[ 0 ]->id;
}

sub _as_string {
   return $_[ 0 ]->vehicle.'-'.local_dt( $_[ 0 ]->period_start )->ymd;
}

sub label {
   return $_[ 0 ]->vehicle.SPC.month_label( $_[ 1 ], $_[ 0 ]->period_start );
}

# Public methods
sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   return $self->next::method;
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $self->validate( TRUE );

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      fields => {
         current_miles      => { validate => 'isMandatory isValidInteger' },
         front_tyre_miles   => { validate => 'isValidInteger' },
         front_tyre_life    => { validate => 'isValidInteger' },
         insurance_due      => { validate => 'isValidDate' },
         last_fueled        => { validate => 'isValidDate' },
         mot_due            => { validate => 'isValidDate' },
         next_service_due   => { validate => 'isValidDate' },
         next_service_miles => { validate => 'isValidInteger' },
         period_start       => { validate => 'isMandatory isValidDate' },
         rear_tyre_miles    => { validate => 'isValidInteger' },
         rear_tyre_life     => { validate => 'isValidInteger' },
         tax_due            => { validate => 'isValidDate' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::VehicleHistory - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::VehicleHistory;
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
