<div>
    <a href="https://gitter.im/pjfl/p5-app-notitia?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=body_badge"><img alt="Gitter" src="https://badges.gitter.im/pjfl/p5-app-notitia.svg"></a>
</div>

# Name

[![Join the chat at https://gitter.im/pjfl/p5-app-notitia](https://badges.gitter.im/pjfl/p5-app-notitia.svg)](https://gitter.im/pjfl/p5-app-notitia?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

App::Notitia - People and resource scheduling

# Synopsis

    # To list the configuration options
    bin/notitia-cli dump-config-attr

    # To start the application server
    plackup bin/notitia-server

# Version

This documents version v0.13.$Rev: 17 $ of **App::Notitia**

# Description

Allows people to book shifts in a rota system. Assets can be assigned
to activities in each shift. Fund raising events can be announced via
a blogging engine and RSS feed

## Features

- 100% Mobile responsive
- Supports an extended flavour of multi-markdown
- Design style similar to that used by Github pages
- Shareable / linkable SEO friendly URLs
- Text searching
- Posts / News / Blog support
- RSS feeds

## Technology

This application is written in modern \[Perl\](http://www.perl.org) and
uses [Moo](https://metacpan.org/pod/Moo), [Plack](https://metacpan.org/pod/Plack), [Web::Simple](https://metacpan.org/pod/Web::Simple), and [DBIC](https://metacpan.org/pod/DBIx::Class). Prefer
class based inheritance when JavaScript programming hence
\[Mootools\](http://mootools.net/) not jQuery.

# Installation

The **App-Notitia** repository contains meta data that lists the CPAN modules
used by the application. Modern Perl CPAN distribution installers (like
[App::cpanminus](https://metacpan.org/pod/App::cpanminus)) use this information to install the required dependencies
when this application is installed.

**Requirements:**

- Perl 5.12.0 or above
- Git - to install **App::Notitia** from Github

To find out if Perl is installed and which version; at a shell prompt type:

    perl -v

To find out if Git is installed, type:

    git --version

If you don't already have it, bootstrap [App::cpanminus](https://metacpan.org/pod/App::cpanminus) with:

    curl -L http://cpanmin.us | perl - --sudo App::cpanminus

What follows are the instructions for a production deployment. If you are
installing for development purposes skip ahead to ["Development Installs"](#development-installs)

If this is a production deployment create a user, `notitia`, and then
login as (`su` to) the `notitia` user before carrying out the next step.

If you `su` to the `notitia` user unset any Perl environment variables first.

Next install [local::lib](https://metacpan.org/pod/local::lib) with:

    cpanm --notest --local-lib=~/local local::lib && \
       eval $(perl -I ~/local/lib/perl5/ -Mlocal::lib=~/local)

The second statement sets environment variables to include the local
Perl library. You can append the output of the `perl` command to your
shell startup if you want to make it permanent. Without the correct
environment settings Perl will not be able to find the installed
dependencies and the following will fail, badly.

Upgrade the installed version of [Module::Build](https://metacpan.org/pod/Module::Build) with:

    cpanm --notest Module::Build

Install **App-Notitia** with:

    cpanm --notest git://github.com/pjfl/p5-app-notitia.git

Watch out for broken Github download URIs, the one above is the
correct format

Although this is a _simple_ application it is composed of many CPAN
distributions and, depending on how many of them are already available,
installation may take a while to complete. The flip side is that there are no
external dependencies like Node.js or Grunt to install. At the risk of
installing broken modules (they are only going into a local library) tests are
skipped by running `cpanm` with the `--notest` option. This has the advantage
that installs take less time but the disadvantage that you will not notice a
broken module until the application fails.

If that fails run it again with the `--force` option:

    cpanm --force git:...

## Development Installs

Assuming you have the Perl environment setup correctly, clone
**App-Notitia** from the repository with:

    git clone https://github.com/pjfl/p5-app-notitia.git Notitia
    cd Notitia/
    cpanm --notest --installdeps .

To install the development toolchain execute:

    cpanm Dist::Zilla
    dzil authordeps | cpanm --notest

## Post Installation

Once installation is complete run the post install:

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
`lib/App/Notitia/app-notitia_local.json`

By default the development server will run at http://localhost:5000 and can be
started in the foreground with:

    plackup bin/notitia-server

Users must authenticate against the `Person` table in the database.
The default user is `admin` password `abc12345`. You should
change that via the change password page, the link for which is on
the account management menu. To start the production server in the
background listening on a Unix socket:

    bin/notitia-daemon start

The `notitia-daemon` program provides normal SysV init script
semantics. Additionally the daemon program will write an `init` script to
standard output in response to the command:

    bin/notitia-daemon get-init-file

As the root user you should redirect this to `/etc/init.d/notitia`, then
restart the notitia service with:

    service notitia restart

Production installs can subsequently be upgraded using this remote `ssh`
command:

    ssh -t <user>@<domain> sudo ~notitia/local/bin/notitia-upgrade

# Configuration and Environment

The prefered production deployment method uses the `FCGI` engine over
a socket to `nginx`. There is an example
\[configuration recipe\](https://www.roxsoft.co.uk/doh/static/en/posts/Blog/Debian-Nginx-Letsencrypt.sh-Configuration-Recipe.html)
for this method of deployment

Running one of the command line programs like `bin/notitia-cli` calling
the `dump-config-attr` method will output a list of configuration options,
their defining class, documentation, and current value

Help for command line options can be found be running:

    bin/notitia-cli list-methods
    bin/notitia-cli help <method>

The `list-methods` command is available to all of the application programs
(except scripts and `notitia-server`)

The bash completion script is provided by:

    . bin/notitia-completion

The following represents a typical `crontab` file for the `notitia` user:

    10 12 * * * /home/notitia/local/bin/notitia-schema -q backup-data
    15 12 * * * /home/notitia/local/bin/notitia-cli -q housekeeping
    20 12 * * * /home/notitia/local/bin/notitia-util -q impending-slot
    25 12 * * * /home/notitia/local/bin/notitia-util -q vacant-slot

A typical logroate configuration in the file `/etc/logrotate.d/notitia`
might look like this:

    /home/notitia/local/var/logs/*.log {
       missingok
       notifempty
       prerotate
          /etc/init.d/notitia stop
          su -c "/home/notitia/local/bin/notitia-jobdaemon stop" notitia
       endscript
       postrotate
          su -c "/home/notitia/local/bin/notitia-jobdaemon start" notitia
          /etc/init.d/notitia start
       endscript
       rotate 4
       sharedscripts
       weekly
    }

# Subroutines/Methods

## `env_var`

    $value = App::Notitia->env_var( 'name', 'new_value' );

Looks up the environment variable and returns it's value. Also acts as a
mutator if provided with an optional new value. Uppercases and prefixes
the environment variable key

## `schema_version`

    $version_object = App::Notitia->schema_version;

Returns the current schema version

# Diagnostics

Exporting `APP_NOTITIA_DEBUG` and setting it to true will cause the
application to log at the debug level. The default log file is
`var/logs/server.log`

Starting the daemon with the `-D` option will cause it to log debug
information to the file `var/logs/daemon.log` and the application will
also start logging at the debug level

By default the production server logs access requests to the file
`var/logs/access.log`

Exporting `DBIC_TRACE` and setting it to true will cause [DBIx::Class](https://metacpan.org/pod/DBIx::Class)
to emit the SQL it generates to `stderr`. On the production server
`stderr` is redirected to `var/tmp/daemon.err`

# Dependencies

- [Class::Usul](https://metacpan.org/pod/Class::Usul)
- [Moo](https://metacpan.org/pod/Moo)
- [Plack](https://metacpan.org/pod/Plack)
- [Web::Components](https://metacpan.org/pod/Web::Components)
- [Web::Simple](https://metacpan.org/pod/Web::Simple)

# Incompatibilities

There are no known incompatibilities in this module

# Bugs and Limitations

If you need help using Notitia, or have found a bug, please create an
issue on the \[Github Repo\](https://github.com/pjfl/p5-app-notitia/issues)

Please note that a Perl module failing to install is not an issue for
_this_ application. Each Perl module has an issues tracker which can
be found via that modules \[Meta::CPAN\](https://metacpan.org) page

# Acknowledgements

I saw \[Daux.io\](https://github.com/justinwalsh/daux.io) on Github and
it said "Fork Me" so I did to create
\[Doh!\](https://github.com/pjfl/p5-app-doh). Code from that project
was used to add a lightweight content management system to
this application

JavaScript libraries hosted by \[CloudFlare\](https://www.cloudflare.com/)

The presentation, layout and styling was taken from the
\[Jekyll\](https://jekyllrb.com/) project

Larry Wall - For the Perl programming language

# Author

Peter Flanigan, `<pjfl@cpan.org>`

# License and Copyright

Copyright (c) 2017 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See [perlartistic](https://metacpan.org/pod/perlartistic)

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE
