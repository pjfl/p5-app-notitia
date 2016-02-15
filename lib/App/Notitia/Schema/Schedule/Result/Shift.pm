package App::Notitia::Schema::Schedule::Result::Shift;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( SHIFT_TYPE_ENUM );
use App::Notitia::Util      qw( enumerated_data_type foreign_key_data_type
                                serial_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'shift' );

$class->add_columns
   ( id      => serial_data_type,
     rota_id => foreign_key_data_type,
     type    => enumerated_data_type( SHIFT_TYPE_ENUM, 'day' ), );

$class->set_primary_key( 'id' );

$class->belongs_to( rota                 => "${result}::Rota", 'rota_id' );
$class->has_many  ( 'controllers'        => "${result}::Slot",
                    { 'foreign.shift_id' => 'self.id' }, { where => {
                       'foreign.type'    => 'controller' } });
$class->has_many  ( 'riders'             => "${result}::Slot",
                    { 'foreign.shift_id' => 'self.id' }, { where => {
                       'foreign.type'    => 'rider' } } );
$class->might_have( 'spare_driver'       => "${result}::Slot",
                    { 'foreign.shift_id' => 'self.id' }, { where => {
                       'foreign.type'    => 'driver' } } );

# Private methods
sub _as_string {
   return $_[ 0 ]->type;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Shift - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Shift;
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
