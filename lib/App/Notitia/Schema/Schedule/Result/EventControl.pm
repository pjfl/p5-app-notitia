package App::Notitia::Schema::Schedule::Result::EventControl;

use strictures;
use parent 'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( FALSE TRUE VARCHAR_MAX_SIZE );
use App::Notitia::DataTypes qw( bool_data_type nullable_foreign_key_data_type
                                varchar_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'event_stream' );

$class->add_columns
   ( status  => bool_data_type( FALSE ),
     sink    => varchar_data_type( 16, 'email' ),
     action  => varchar_data_type( 32 ),
     role_id => nullable_foreign_key_data_type,
     notes   => varchar_data_type,
     );

$class->set_primary_key( 'sink', 'action' );

$class->belongs_to( role => "${result}::Type", 'role_id', $left_join );

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
         action   => { max_length => 32, min_length =>  8, },
         notes    => { max_length => VARCHAR_MAX_SIZE(), min_length =>  0, },
         sink     => { max_length => 16, min_length =>  3, },
      },
      fields          => {
         action       => {
            validate  => 'isMandatory isValidLength isValidIdentifier' },
         notes        => {
            validate  => 'isValidLength isValidText' },
         sink         => {
            validate  => 'isMandatory isValidLength isValidIdentifier' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::EventControl - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::EventControl;
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
