---
title: Getting Started
---

**Notitia** allows people to book shifts in a rota system. Assets
can be assigned to activities in each shift. Fund raising events
are announced via a blogging engine and RSS feed

#### Features

* 100% Mobile responsive
* Supports an extended flavour of multi-markdown
* Design style similar to that used by Github pages
* Shareable / linkable SEO friendly URLs
* Text searching
* Posts / News / Blog support
* RSS feeds

#### Technology

This application is written in modern [Perl](http://www.perl.org) and
uses [Moo](https://metacpan.org/module/Moo),
[Plack](https://metacpan.org/module/Plack),
[Web::Simple](https://metacpan.org/module/Web::Simple), and
[DBIC](https://metacpan.org/module/DBIx::Class). Prefer
class based inheritance when JavaScript programming hence
[Mootools](http://mootools.net/) not jQuery.

#### Installation

The [App-Notitia repository](http://github.com/pjfl/p5-app-notitia)
contains meta data that lists the CPAN modules used by the
application. Modern Perl CPAN distribution installers (like
[App::cpanminus](https://metacpan.org/module/App::cpanminus))
use this information to install the required dependencies when this
application is installed.

**Requirements:**

* Perl 5.12.0 or above
* Git - to install **App::Notitia** from Github

To find out if Perl is installed and which version; at a shell prompt type

```shell
   perl -v
```
To find out if Git is installed, type

```shell
   git --version
```

If you don't already have it, bootstrap
[App::cpanminus](https://metacpan.org/module/App::cpanminus) with:

```shell
   curl -L http://cpanmin.us | perl - --sudo App::cpanminus
```

What follows are the instructions for a production deployment. If you are
installing for development purposes skip ahead to Development Installs

Next install [local::lib](https://metacpan.org/module/local::lib) with:

```shell
   cpanm --notest --local-lib=~/local local::lib && \
      eval $(perl -I ~/local/lib/perl5/ -Mlocal::lib=~/local)
```

The second statement sets environment variables to include the local
Perl library. You can append the output of the perl command to your
shell startup if you want to make it permanent. Without the correct
environment settings Perl will not be able to find the installed
dependencies and the following will fail, badly.

Install **App-Notitia** with:

```shell
   cpanm --notest git://github.com/pjfl/p5-app-notitia.git
```

Watch out for broken Github download URIs, the one above is the
correct format

Although this is a *simple* application it is composed of many CPAN
distributions and, depending on how many of them are already
available, installation may take a while to complete. The flip side is
that there are no external dependencies like Node.js or Grunt to
install. Anyway you are advised to seek out sustenance whilst you
wait for ack-2.12 to run it's tests.  At the risk of installing broken
modules (they are only going into a local library) you can skip the
tests by running `cpanm` with the `--notest` option.

If that fails run it again with the `--force` option

```shell
   cpanm --force git:...
```

#### Development Installs

Assuming you have the Perl environment setup correctly, clone
**App-Notitia** from the repository with

```shell
   git clone https://github.com/pjfl/p5-app-notitia.git Notitia
   cd Notitia/
   cpanm --notest --installdeps .
```

To install the development toolchain execute

```shell
   cpanm Dist::Zilla
   dzil authordeps | cpanm --notest
```

#### Post Installation

Once installation is complete run the post install

```shell
   bin/notitia-cli post-install
```

This will allow you to edit the credentials that the application will
use to connect to the database, it then creates that user and the
database schema. Next it populates the database with initial data
including creating an administration user. You will need the database
administration password to complete this step

For the user name generation to work you will need to edit the configuration
file *lib/App/Notitia/app-notitia.json* and add the line

```json
   "person_prefix": "xxx",
```

substituting a two or three character prefix for *xxx* that reflects the
name of the organisation that is operating the application

By default the development server will run at:
[http://localhost:5000](http://localhost:5000) and can be started in
the foreground with:

```shell
   plackup bin/notitia-server
```

Users must authenticate against the `Person` table in the database.
The default user is `admin` password `12345678`. You should
change that via the change password page the link for which is at
the top of the default page. To start the production server in the
background listening on the default port 8085 use:

```shell
   bin/notiita-daemon start
```

The `notitia-daemon` program provides normal SysV init script
semantics. Additionally the daemon program will write an init script to
standard output in response to the command:

```shell
   bin/notitia-daemon get-init-file
```
#### Acknowledgements

I saw [Daux.io](https://github.com/justinwalsh/daux.io) on Github and
it said "Fork Me" so I did to create
[Doh!](https://github.com/pjfl/p5-app-doh). Code from that project
was used to add a lightweight content management system to
this application

JavaScript libraries hosted by [CloudFlare](https://www.cloudflare.com/).

The presentation, layout and styling was taken from the
[Jekyll](https://jekyllrb.com/) project.

#### Support

If you need help using Notitia, or have found a bug, please create an
issue on the <a href="https://github.com/pjfl/p5-app-notitia/issues"
target="_blank">Github repo</a>.

Please note that a Perl module failing to install is not an issue for
*this* application. Each Perl module has an issues tracker which can
be found via that modules [Meta::CPAN](https://metacpan.org) page
