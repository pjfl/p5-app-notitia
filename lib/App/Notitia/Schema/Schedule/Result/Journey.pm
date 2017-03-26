package App::Notitia::Schema::Schedule::Result::Journey;

use strictures;
use parent 'App::Notitia::Schema::Schedule::Base::Result';

use App::Notitia::Constants qw( FALSE NUL PRIORITY_TYPE_ENUM SPC
                                TRUE VARCHAR_MAX_SIZE );
use App::Notitia::DataTypes qw( bool_data_type date_data_type
                                enumerated_data_type foreign_key_data_type
                                serial_data_type
                                set_on_create_datetime_data_type
                                varchar_data_type );
use App::Notitia::Util      qw( datetime_label );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'journey' );

$class->add_columns
   ( id                => serial_data_type,
     completed         => bool_data_type( FALSE ),
     priority          => enumerated_data_type( PRIORITY_TYPE_ENUM, 'routine' ),
     original_priority => enumerated_data_type( PRIORITY_TYPE_ENUM, 'routine' ),
     created           => set_on_create_datetime_data_type,
     requested         => date_data_type,
     delivered         => date_data_type,
     controller_id     => foreign_key_data_type,
     customer_id       => foreign_key_data_type,
     pickup_id         => foreign_key_data_type,
     dropoff_id        => foreign_key_data_type,
     notes             => varchar_data_type,
     );

$class->set_primary_key( 'id' );

$class->belongs_to( controller => "${result}::Person",   'controller_id' );
$class->belongs_to( customer   => "${result}::Customer", 'customer_id' );
$class->belongs_to( dropoff    => "${result}::Location", 'dropoff_id' );
$class->belongs_to( pickup     => "${result}::Location", 'pickup_id' );

$class->has_many( legs => "${result}::Leg", 'journey_id' );
$class->has_many( packages => "${result}::Package", 'journey_id' );

# Public methods
sub consignment {
   my $self = shift; my $r = NUL;

   for my $package ($self->packages->all) {
      $r and $r .= ', ';
      $r .= $package->package_type.' x '.$package->quantity.SPC
         . ($package->description ? '('.$package->description.')' : NUL );
   }

   return $r;
}

sub created_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->created;
}

sub delivered_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->delivered;
}

sub insert {
   my $self    = shift;
   my $columns = { $self->get_inflated_columns };

   $columns->{original_priority} = $columns->{priority};

   $self->set_inflated_columns( $columns );

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   return $self->next::method;
}

sub requested_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->requested;
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $self->validate( TRUE );

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints      => {
         notes         => { max_length => VARCHAR_MAX_SIZE(), min_length => 0 },
      },
      fields           => {
         customer_id   => { validate => 'isMandatory' },
         dropoff_id    => { validate => 'isMandatory' },
         notes         => { validate => 'isValidLength isValidText' },
         pickup_id     => { validate => 'isMandatory' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Journey - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Journey;
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
