package App::Notitia;

use 5.010001;
use strictures;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 46 $ =~ /\d+/gmx );

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

This documents version v0.3.$Rev: 46 $ of B<App::Notitia>

=head1 Description

Allows people to book shifts in a rota system. Assets can be assigned
to activities in each shift. Fund raising events can be announced via
a blogging engine and RSS feed

=head2 Features

=over 3

=item 100% Mobile responsive

=item Supports an extended flavour of multi-markdown

=item Design style similar to that used by Github pages

=item Shareable / linkable SEO friendly URLs

=item Text searching

=item Posts / News / Blog support

=item RSS feeds

=back

=head2 Technology

This application is written in modern [Perl](http://www.perl.org) and
uses L<Moo>, L<Plack>, L<Web::Simple>, and L<DBIC|DBIx::Class>. Prefer
class based inheritance when JavaScript programming hence
[Mootools](http://mootools.net/) not jQuery.

=head1 Installation

The B<App-Notitia> repository contains meta data that lists the CPAN modules
used by the application. Modern Perl CPAN distribution installers (like
L<App::cpanminus>) use this information to install the required dependencies
when this application is installed.

B<Requirements:>

=over 3

=item Perl 5.12.0 or above

=item Git - to install B<App::Notitia> from Github

=back

To find out if Perl is installed and which version; at a shell prompt type

   perl -v

To find out if Git is installed, type

   git --version

If you don't already have it, bootstrap L<App::cpanminus> with:

   curl -L http://cpanmin.us | perl - --sudo App::cpanminus

What follows are the instructions for a production deployment. If you are
installing for development purposes skip ahead to L</Development Installs>

Next install L<local::lib> with:

   cpanm --notest --local-lib=~/local local::lib && \
      eval $(perl -I ~/local/lib/perl5/ -Mlocal::lib=~/local)

The second statement sets environment variables to include the local
Perl library. You can append the output of the perl command to your
shell startup if you want to make it permanent. Without the correct
environment settings Perl will not be able to find the installed
dependencies and the following will fail, badly.

Upgrade the installed version of L<Module::Build> with

   cpanm --notest Module::Build

Install B<App-Notitia> with:

   cpanm --notest git://github.com/pjfl/p5-app-notitia.git

Watch out for broken Github download URIs, the one above is the
correct format

Although this is a I<simple> application it is composed of many CPAN
distributions and, depending on how many of them are already
available, installation may take a while to complete. The flip side is
that there are no external dependencies like Node.js or Grunt to
install. Anyway you are advised to seek out sustenance whilst you
wait for ack-2.12 to run it's tests.  At the risk of installing broken
modules (they are only going into a local library) you can skip the
tests by running C<cpanm> with the C<--notest> option.

If that fails run it again with the C<--force> option

   cpanm --force git:...

=head2 Development Installs

Assuming you have the Perl environment setup correctly, clone
B<App-Notitia> from the repository with

   git clone https://github.com/pjfl/p5-app-notitia.git Notitia
   cd Notitia/
   cpanm --notest --installdeps .

To install the development toolchain execute

   cpanm Dist::Zilla
   dzil authordeps | cpanm --notest

=head2 Post Installation

Once installation is complete run the post install

   bin/notitia-cli post-install

This will allow you to edit the credentials that the application will
use to connect to the database, it then creates that user and the
database schema. Next it populates the database with initial data
including creating an administration user. You will need the database
administration password to complete this step

For the user name generation to work you will be prompted to enter a two or
three character string that reflects the name of the organisation that is
operating the application. If one is not entered then a random one will
be generated. This information will be stored in the file
F<lib/App/Notitia/app-notitia_local.json>

By default the development server will run at http://localhost:5000 and can be
started in the foreground with:

   plackup bin/notitia-server

Users must authenticate against the C<Person> table in the database.
The default user is C<admin> password C<12345678>. You should
change that via the change password page the link for which is at
the top of the default page. To start the production server in the
background listening on a Unix socket:

   bin/notitia-daemon start

The C<notitia-daemon> program provides normal SysV init script
semantics. Additionally the daemon program will write an init script to
standard output in response to the command:

   bin/notitia-daemon get-init-file

=head1 Configuration and Environment

Running one of the command line programs like F<bin/notitia-cli> calling
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

By default the production server logs access requests to the file
F<var/logs/access.log>

Exporting C<DBIC_TRACE> and setting it to true will cause L<DBIx::Class>
to emit the SQL it generates to C<stderr>. On the production server
C<stderr> is redirected to F<var/tmp/daemon.err>

=head1 Project To Do List

TODO: Limit list lengths when number of users increases

TODO: Add media query to reduce form size on mobiles

TODO: Colour pallette issues. Logo

TODO: Add editor role. Someone who can edit documents

TODO: Event delettion leaves a left over event post

TODO: Schema version numbers. DDL files ignored by git

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

If you need help using Notitia, or have found a bug, please create an
issue on the [Github Repo](https://github.com/pjfl/p5-app-notitia/issues)

Please note that a Perl module failing to install is not an issue for
I<this> application. Each Perl module has an issues tracker which can
be found via that modules [Meta::CPAN](https://metacpan.org) page

=head1 Acknowledgements

I saw [Daux.io](https://github.com/justinwalsh/daux.io) on Github and
it said "Fork Me" so I did to create
[Doh!](https://github.com/pjfl/p5-app-doh). Code from that project
was used to add a lightweight content management system to
this application

JavaScript libraries hosted by [CloudFlare](https://www.cloudflare.com/)

The presentation, layout and styling was taken from the
[Jekyll](https://jekyllrb.com/) project

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
