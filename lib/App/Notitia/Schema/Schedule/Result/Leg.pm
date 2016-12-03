package App::Notitia::Schema::Schedule::Result::Leg;

use strictures;
use parent 'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( TRUE );
use App::Notitia::DataTypes qw( date_data_type foreign_key_data_type
                                nullable_foreign_key_data_type serial_data_type
                                set_on_create_datetime_data_type );
use App::Notitia::Util      qw( datetime_label locm );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'leg' );

$class->add_columns
   (  id             => serial_data_type,
      journey_id     => foreign_key_data_type,
      operator_id    => foreign_key_data_type,
      beginning_id   => foreign_key_data_type,
      ending_id      => foreign_key_data_type,
      vehicle_id     => nullable_foreign_key_data_type,
      created        => set_on_create_datetime_data_type,
      called         => date_data_type,
      collection_eta => date_data_type,
      collected      => date_data_type,
      delivered      => date_data_type,
      on_station     => date_data_type,
      );

$class->set_primary_key( 'id' );

$class->belongs_to( beginning => "${result}::Location", 'beginning_id' );
$class->belongs_to( ending    => "${result}::Location", 'ending_id'    );
$class->belongs_to( journey   => "${result}::Journey",  'journey_id'   );
$class->belongs_to( operator  => "${result}::Person",   'operator_id'  );
$class->belongs_to( vehicle   => "${result}::Vehicle",  'vehicle_id'   );

# Public methods
sub called_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->called;
}

sub created_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->created;
}

sub collection_eta_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->collection_eta;
}

sub collected_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->collected;
}

sub delivered_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->delivered;
}

sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   return $self->next::method;
}

sub label {
   my ($self, $req) = @_;

   return locm( $req, $self->beginning ).' ('.$self->called_label( $req ).')';
}

sub on_station_label {
   return datetime_label $_[ 1 ], $_[ 0 ]->on_station;
}

sub status {
   my $self = shift;

   $self->on_station and return 'on_station';
   $self->delivered  and return 'delivered';
   $self->collected  and return 'collected';

   return 'called';
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $self->validate( TRUE );

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      fields            => {
         beginning_id   => { validate => 'isMandatory' },
         called         => { validate => 'isValidDate' },
         collection_eta => { validate => 'isValidDate' },
         collected      => { validate => 'isValidDate' },
         delivered      => { validate => 'isValidDate' },
         ending_id      => { validate => 'isMandatory' },
         on_station     => { validate => 'isValidDate' },
         operator_id    => { validate => 'isMandatory' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Leg - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Leg;
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
