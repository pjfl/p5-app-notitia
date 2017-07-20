package App::Notitia::DataTypes;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Constants qw( FALSE NUL TRUE VARCHAR_MAX_SIZE );

our @EXPORT_OK = qw( bool_data_type date_data_type enumerated_data_type
                     foreign_key_data_type nullable_foreign_key_data_type
                     nullable_numerical_id_data_type nullable_varchar_data_type
                     numerical_id_data_type serial_data_type
                     set_on_create_datetime_data_type
                     unsigned_int_data_type varchar_data_type );

# Public functions
sub bool_data_type (;$) {
   return { data_type     => 'boolean',
            default_value => $_[ 0 ] // FALSE,
            is_nullable   => FALSE, };
}

sub date_data_type () {
   return { data_type     => 'datetime',
            is_nullable   => TRUE,
            datetime_undef_if_invalid => TRUE,
            timezone      => 'GMT', };
}

sub enumerated_data_type ($;$) {
   return { data_type     => 'enum',
            default_value => $_[ 1 ],
            extra         => { list => $_[ 0 ] },
            is_enum       => TRUE, };
}

sub foreign_key_data_type (;$$) {
   my $type_info = { data_type     => 'integer',
                     default_value => $_[ 0 ],
                     extra         => { unsigned => TRUE },
                     is_nullable   => FALSE,
                     is_numeric    => TRUE, };

   defined $_[ 1 ] and $type_info->{accessor} = $_[ 1 ];

   return $type_info;
}

sub nullable_foreign_key_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_nullable       => TRUE,
            is_numeric        => TRUE, };
}

sub nullable_numerical_id_data_type () {
   return { data_type         => 'smallint',
            default_value     => undef,
            is_nullable       => TRUE,
            is_numeric        => TRUE, };
}

sub nullable_varchar_data_type (;$$) {
   return { data_type         => 'varchar',
            default_value     => $_[ 1 ],
            is_nullable       => TRUE,
            size              => $_[ 0 ] || VARCHAR_MAX_SIZE, };
}

sub numerical_id_data_type (;$) {
   return { data_type         => 'smallint',
            default_value     => $_[ 0 ],
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub serial_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_auto_increment => TRUE,
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub set_on_create_datetime_data_type () {
   return { %{ date_data_type() }, set_on_create => TRUE };
}

sub unsigned_int_data_type (;$$) {
   my $type_info = { data_type     => 'integer',
                     default_value => $_[ 0 ],
                     extra         => { unsigned => TRUE },
                     is_nullable   => FALSE,
                     is_numeric    => TRUE, };

   defined $_[ 1 ] and $type_info->{accessor} = $_[ 1 ];

   return $type_info;
}

sub varchar_data_type (;$$) {
   return { data_type         => 'varchar',
            default_value     => $_[ 1 ] // NUL,
            is_nullable       => FALSE,
            size              => $_[ 0 ] || VARCHAR_MAX_SIZE, };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::DataTypes - People and resource scheduling

=head1 Synopsis

   use App::Notitia::DataTypes;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=item C<bool_data_type>

=item C<date_data_type>

=item C<enumerated_data_type>

=item C<foreign_key_data_type>

=item C<nullable_foreign_key_data_type>

=item C<nullable_numerical_id_data_type>

=item C<nullable_varchar_data_type>

=item C<numerical_id_data_type>

=item C<serial_data_type>

=item C<set_on_create_datetime_data_type>

=item C<varchar_data_type>

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
