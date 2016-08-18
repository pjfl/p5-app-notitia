package App::Notitia::Schema::Schedule::Result::Leg;

use strictures;
use parent 'App::Notitia::Schema::Base';

use App::Notitia::Util qw( date_data_type foreign_key_data_type
                           serial_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'leg' );

$class->add_columns
   (  id             => serial_data_type,
      journey_id     => foreign_key_data_type,
      person_id      => foreign_key_data_type,
      vehicle_id     => foreign_key_data_type,
      beginning_id   => foreign_key_data_type,
      ending_id      => foreign_key_data_type,
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
$class->belongs_to( body      => "${result}::Person",   'person_id'    );
$class->belongs_to( vehicle   => "${result}::Vehicle",  'vehicle_id'   );

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
