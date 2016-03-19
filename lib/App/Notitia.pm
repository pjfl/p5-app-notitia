package App::Notitia;

use 5.010001;
use strictures;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 41 $ =~ /\d+/gmx );

use Class::Usul::Functions  qw( ns_environment );

sub env_var {
   return ns_environment __PACKAGE__, $_[ 1 ], $_[ 2 ];
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia - People and resource scheduling

=head1 Synopsis

   # To list the configuration options
   bin/notitia-cli dump-config-attr

   # To start the application server
   plackup bin/notitia-server

=head1 Version

This documents version v0.2.$Rev: 41 $ of L<App::Notitia>

=head1 Description

Allows people to book shifts in a rota system. Assets can be assigned
to activities in each shift. Fund raising events can be announced via
a blogging engine and RSS feed

=head1 Configuration and Environment

Running one of the command line programs like C<bin/notitia-cli> calling
the C<dump-config-attr> method will output a list of configuration options,
their defining class, documentation, and current value

Help for command line options can be found be running

   bin/notitia-cli list-methods

The production server options are detailed by running

   bin/notitia-daemon list-methods

=head1 Subroutines/Methods

=head2 C<env_var>

   $value = App::Notitia->env_var( 'name', 'new_value' );

Looks up the environment variable and returns it's value. Also acts as a
mutator if provided with an optional new value. Uppercases and prefixes
the environment variable key

=head1 Diagnostics

Exporting C<APP_NOTITIA_DEBUG> and setting it to true will cause the
application to log at the debug level. The default log file is
F<var/logs/server.log>

Starting the daemon with the C<-D> option will cause it to log debug
information to the file F<var/logs/daemon.log> and the application will
also start logging at the debug level

The production server logs access requests to the file
F<var/logs/access_8085.log>

Exporting C<DBIC_TRACE> and setting it to true will cause L<DBIx::Class>
to emit the SQL it generates to C<stderr>

=head1 Project To Do List

TODO: Setup a virtualbox environment to do Explorer testing

TODO: Determine how to request a vehicle for an event

TODO: Vehicle assigning should be moved to Slot to make URI more restful

TODO: Endorsement type_codes need similar treatment to event uris

TODO: Need calendar view for whole month

TODO: Make bike_requested appear with some text

TODO: Loose traffic lights from rota

TODO: Make some of the docs pages private

TODO: Rename asset_manager to rota_manager and allow to unassign slots

TODO: Add a participents dialog to rota event row

TODO: Blank event row on rota take you to event create

TODO: Separate login page from index page

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moo>

=item L<Plack>

=item L<Web::Components>

=item L<Web::Simple>

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
