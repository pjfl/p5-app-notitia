package App::Notitia::Schema::Schedule::Result::UserField;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent 'App::Notitia::Schema::Schedule::Base::Result';

use App::Notitia::Constants qw( FIELD_TYPE_ENUM FALSE TRUE );
use App::Notitia::DataTypes qw( bool_data_type
                                enumerated_data_type
                                foreign_key_data_type
                                nullable_foreign_key_data_type
                                nullable_numerical_id_data_type
                                nullable_varchar_data_type
                                numerical_id_data_type
                                varchar_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'user_field' );

$class->add_columns
   ( form_id         => foreign_key_data_type,
     name            => varchar_data_type( 64 ),
     field_type      => enumerated_data_type( FIELD_TYPE_ENUM, 'textfield' ),
     field_group_id  => nullable_foreign_key_data_type,
     order           => numerical_id_data_type,
     class           => nullable_varchar_data_type( 64 ),
     container_class => nullable_varchar_data_type( 64 ),
     disabled        => bool_data_type,
     fieldsize       => nullable_numerical_id_data_type,
     label           => nullable_varchar_data_type,
     label_class     => nullable_varchar_data_type( 64 ),
     maxlength       => nullable_numerical_id_data_type,
     placeholder     => nullable_varchar_data_type,
     tip             => nullable_varchar_data_type,
     value           => nullable_varchar_data_type( 1024 ),
     );

$class->set_primary_key( 'form_id', 'name' );

$class->belongs_to( form => "${result}::UserForm", 'form_id' );

$class->belongs_to( field_group => "${result}::FieldGroup",
                    'field_group_id', $left_join );

# Private methods
sub _as_string {
   return $_[ 0 ]->form.'.'.$_[ 0 ]->name;
}


1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::UserField - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::UserField;
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
