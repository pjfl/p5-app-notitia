package App::Notitia::Schema::Schedule::Result::Location;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent 'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( TRUE );
use App::Notitia::Util      qw( serial_data_type varchar_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'location' );

$class->add_columns
   ( id      => serial_data_type,
     address => varchar_data_type( 64 ), );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'address' ] );

$class->has_many( beginnings => "${result}::Leg",      'beginning_id' );
$class->has_many( dropoffs   => "${result}::Journey",  'dropoff_id'   );
$class->has_many( endings    => "${result}::Leg",      'ending_id'    );
$class->has_many( pickups    => "${result}::Journey",  'pickup_id'    );

# Private methods
sub _as_string {
   return $_[ 0 ]->address;
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
      constraints => {
         address  => { max_length => 64, min_length => 5, },
      },
      fields      => {
         address  => { validate => 'isValidLength isValidText' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Location - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Location;
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
