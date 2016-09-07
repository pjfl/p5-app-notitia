package App::Notitia::Schema::Schedule::Result::Accused;

use strictures;
use parent 'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( FALSE TRUE );
use App::Notitia::Util      qw( foreign_key_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'accused' );

$class->add_columns
   ( incident_id => foreign_key_data_type,
     accused_id  => foreign_key_data_type,
     );

$class->set_primary_key( 'incident_id', 'accused_id' );

$class->belongs_to( incident => "${result}::Incident", 'incident_id' );
$class->belongs_to( person   => "${result}::Person",   'accused_id'  );

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Accused - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Accused;
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
