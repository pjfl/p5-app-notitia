package App::Notitia::Schema::Schedule::Result::Vehicle;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Util qw( foreign_key_data_type
                           nullable_foreign_key_data_type
                           serial_data_type varchar_data_type );
use Scalar::Util       qw( blessed );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'vehicle' );

$class->add_columns
   ( id       => serial_data_type,
     type_id  => foreign_key_data_type,
     owner_id => nullable_foreign_key_data_type,
     aquired  => { data_type => 'datetime' },
     disposed => { data_type => 'datetime' },
     vrn      => varchar_data_type( 16 ),
     name     => varchar_data_type( 64 ),
     notes    => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'vrn' ] );

$class->belongs_to( owner => "${result}::Person", 'owner_id',
                    { join_type => 'left' } );
$class->belongs_to( type  => "${result}::Type", 'type_id' );

# Private methods
sub _as_string {
   return $_[ 0 ]->name ? $_[ 0 ]->name : $_[ 0 ]->vrn;
}

my $_find_type_by = sub {
   my ($self, $name, $type) = @_;

   return $self->result_source->schema->resultset( 'Type' )->search
      ( { name => $name, type => $type } )->single;
};

my $_find_vehicle_type = sub {
   return $_[ 0 ]->$_find_type_by( $_[ 1 ], 'vehicle' );
};

# Public methods
sub insert {
   my $self    = shift;
   my $columns = { $self->get_inflated_columns };
   my $type    = $columns->{type_id};

   $type and $type !~ m{ \A \d+ \z }mx
         and $columns->{type_id} = $self->$_find_vehicle_type( $type )->id;

   $self->set_inflated_columns( $columns );

#   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   return $self->next::method;
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
