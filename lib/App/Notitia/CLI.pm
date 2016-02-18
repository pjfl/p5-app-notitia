package App::Notitia::CLI;

use namespace::autoclean;

use App::Notitia; our $VERSION = $App::Doh::VERSION;

use Archive::Tar::Constant qw( COMPRESS_GZIP );
use Class::Usul::Constants qw( FALSE NUL OK TRUE );
use Class::Usul::Functions qw( class2appdir ensure_class_loaded io );
use Class::Usul::Types     qw( LoadableClass NonEmptySimpleStr Object );
use English                qw( -no_match_vars );
use User::grent;
use User::pwent;
use Moo;
use Class::Usul::Options;

extends q(Class::Usul::Programs);

# Attribute constructors
my $_build_less = sub {
   my $self = shift; my $conf = $self->config;

   return $self->less_class->new
      ( compress      =>   $conf->compress_css,
        include_paths => [ $conf->root->catdir( 'less' )->pathname ],
        tmp_path      =>   $conf->tempdir, );
};

# Public attributes
option 'skin'         => is => 'lazy', isa => NonEmptySimpleStr, format => 's',
   documentation      => 'Name of the skin to operate on',
   builder            => sub { $_[ 0 ]->config->skin }, short => 's';

has '+config_class'   => default => 'App::Notitia::Config';

has 'less'            => is => 'lazy', isa => Object, builder => $_build_less;

has 'less_class'      => is => 'lazy', isa => LoadableClass,
   default            => 'CSS::LESS';

# Private functions
my $_init_file_list = sub {
   return io[ NUL, 'etc', 'init.d', $_[ 0 ] ],
          io[ NUL, 'etc', 'rc0.d', 'K01'.$_[ 0 ] ];
};

# Private methods
my $_write_theme = sub {
   my ($self, $cssd, $file) = @_;

   my $skin = $self->skin;
   my $conf = $self->config;
   my $path = $conf->root->catfile( $conf->less, $skin, "${file}.less" );

   $path->exists or return;

   my $css  = $self->less->compile( $path->all );

   $self->info( 'Writing theme file [_1]', { args => [ "${skin}-${file}" ] } );
   $cssd->catfile( "${skin}-${file}.css" )->println( $css );
   return;
};

# Public methods
sub make_css : method {
   my $self = shift;
   my $conf = $self->config;
   my $cssd = $conf->root->catdir( $conf->css );

   if (my $file = $self->next_argv) { $self->$_write_theme( $cssd, $file ) }
   else { $self->$_write_theme( $cssd, $_ ) for (@{ $conf->less_files }) }

   return OK;
}

sub make_skin : method {
   my $self = shift; my $conf = $self->config; my $skin = $self->skin;

   ensure_class_loaded 'Archive::Tar'; my $arc = Archive::Tar->new;

   for my $path ($conf->root->catdir( $conf->less, $skin )->all_files) {
      $arc->add_files( $path->abs2rel( $conf->appldir ) );
   }

   for my $path ($conf->root->catdir( 'templates', $skin )->all_files) {
      $arc->add_files( $path->abs2rel( $conf->appldir ) );
   }

   my $path = $conf->root->catfile( $conf->js, "${skin}.js" );

   $arc->add_files( $path->abs2rel( $conf->appldir ) );
   $self->info( 'Generating tarball for [_1] skin', { args => [ $skin ] } );
   $arc->write( "${skin}-skin.tgz", COMPRESS_GZIP );
   return OK;
}

sub post_install : method {
   my $self     = shift;
   my $conf     = $self->config;
   my $appldir  = $conf->appldir;
   my $verdir   = $appldir->basename;
   my $localdir = $appldir->catdir( 'local' );
   my $appname  = class2appdir $conf->appclass;
   my $inc      = $localdir->catdir( 'lib', 'perl5'   );
   my $profile  = $localdir->catdir( 'var', 'etc', 'profile' );
   my $cmd      = [ $EXECUTABLE_NAME, '-I', "${inc}",
                    "-Mlocal::lib=${localdir}" ];

   $localdir->exists
      and $profile->assert_filepath
      and $self->run_cmd( $cmd, { err => 'stderr', out => $profile } );

   if ($verdir =~ m{ \A v \d+ \. \d+ p (\d+) \z }msx) {
      my $owner = my $group = $conf->owner;

      getgr( $group ) or $self->run_cmd( [ 'groupadd', '--system', $group ] );

      unless (getpwnam( $owner )) {
         $self->run_cmd( [ 'useradd', '--home', $conf->user_home, '--gid',
                           $group, '--no-user-group', '--system', $owner  ] );
         $self->run_cmd( [ 'chown', "${owner}:${group}", $conf->user_home ] );
      }

      $self->run_cmd( [ 'chown', "${owner}:${group}", $appldir ] );
      $self->run_cmd( [ 'chown', '-R', "${owner}:${group}", $appldir ] );
   }

   my ($init, $kill) = $_init_file_list->( $appname );

   $cmd = [ $conf->binsdir->catfile( 'notifier-daemon' ), 'get-init-file' ];

   $init->exists or $self->run_cmd( $cmd, { out => $init } );
   $init->is_executable or $init->chmod( 0750 );
   $kill->exists or $self->run_cmd( [ 'update-rc.d', $appname, 'defaults' ] );
   return OK;
}

sub uninstall : method {
   my $self    = shift;
   my $conf    = $self->config;
   my $appname = class2appdir $conf->appclass;

   my ($init, $kill) = $_init_file_list->( $appname );

   $init->exists and $self->run_cmd( [ 'invoke-rc.d', $appname, 'stop' ],
                                     { expected_rv => 1 } );
   $kill->exists and $self->run_cmd( [ 'update-rc.d', $appname, 'remove' ] );
   $init->unlink;
   return OK;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::CLI - People and resource scheduling

=head1 Synopsis

   use App::Notitia::CLI;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head2 C<make_css> - Compile CSS files from LESS files

   bin/notitia-cli make-css [theme]

Creates CSS files under F<var/root/css> one for each colour theme. If a colour
theme name is supplied only the C<LESS> for that theme is compiled

=head2 C<make_skin> - Make a tarball of the files for a skin

   bin/notitia-cli -s name_of_skin make-skin

Creates a tarball in the current directory containing the C<LESS>
files, templates, and JavaScript code for the named skin. Defaults to the
F<hyde> skin

=head2 C<post_install> - Perform post installation tasks

   bin/notitia-cli post-install

Performs a sequence of tasks after installation of the applications files
is complete

=head2 C<uninstall> - Remove the application from the system

   bin/notitia-cli uninstall

Uninstalls the application

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
