package App::Notitia::Schema::Schedule::Result::Rota;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Util qw( date_data_type foreign_key_data_type
                           serial_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'rota' );

$class->add_columns
   ( id      => serial_data_type,
     type_id => foreign_key_data_type,
     date    => date_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'type_id', 'date' ] );
# TODO: Add index for date
$class->belongs_to( type   => "${result}::Type",  'type_id' );
$class->has_many  ( events => "${result}::Event", 'start_rota_id' );
$class->has_many  ( shifts => "${result}::Shift", 'rota_id' );

# Private methods
sub _as_string {
   return $_[ 0 ]->date;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Rota - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Rota;
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
