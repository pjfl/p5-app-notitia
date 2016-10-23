package App::Notitia::CLI;

use namespace::autoclean;

use App::Notitia; our $VERSION = $App::Doh::VERSION;

use Archive::Tar::Constant   qw( COMPRESS_GZIP );
use Class::Usul::Constants   qw( AS_PARA AS_PASSWORD FALSE NUL OK TRUE );
use Class::Usul::Crypt::Util qw( encrypt_for_config );
use Class::Usul::File;
use Class::Usul::Functions   qw( bson64id class2appdir create_token
                                 ensure_class_loaded io );
use Class::Usul::Types       qw( LoadableClass NonEmptySimpleStr Object );
use English                  qw( -no_match_vars );
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
        include_paths => [ $conf->vardir->catdir( $conf->less )->pathname ],
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
   return io( [ NUL, 'etc', 'init.d', $_[ 0 ] ] ),
          io( [ NUL, 'etc', 'rc0.d', 'K01'.$_[ 0 ] ] );
};

my $_random_chars = sub {
   my $token = create_token; $token =~ s{ [^a-z]+ }{}gmx; return $token;
};

# Private methods
my $_create_profile = sub {
   my ($self, $localdir) = @_; my ($cmd, $profile);

   if ($localdir->exists) {
      my $inc = $localdir->catdir( 'lib', 'perl5' );

      $cmd = [ $EXECUTABLE_NAME, '-I', "${inc}", "-Mlocal::lib=${localdir}" ];
      $profile = $localdir->catfile( qw( var etc profile ) );
   }
   else {
      $localdir = io[ '~', 'local' ];

      my $inc = $localdir->catdir( 'lib', 'perl5' );

      $cmd = [ $EXECUTABLE_NAME, '-I', "${inc}", "-Mlocal::lib=${localdir}" ];
      $profile = $self->config->vardir->catfile( 'etc', 'profile' );
   }

   unless ($profile->exists) {
      delete $ENV{PERL5LIB}; delete $ENV{PERL_LOCAL_LIB_ROOT};
      $self->run_cmd( $cmd, { err => 'stderr', out => $profile } );
   }

   return;
};

my $_create_schema = sub {
   my ($self, $cmd) = @_;

   my $opts = { err => 'stderr', in => 'stdin', out => 'stdout' };

   $self->run_cmd( [ $cmd, '-o', 'bootstrap=1', 'edit-credentials' ], $opts );
   $opts->{expected_rv} = 1;
   $self->run_cmd( [ $cmd, 'drop-database' ], $opts );
   delete $opts->{expected_rv};
   $self->run_cmd( [ $cmd, 'create-database' ], $opts );
   $self->run_cmd( [ $cmd, 'deploy-and-populate' ], $opts );
   return;
};

my $_root_post_install = sub {
   my ($self, $appldir) = @_;

   my $conf = $self->config; my $verdir = $appldir->basename;

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

   my $appname = class2appdir $conf->appclass;
   my ($init, $kill) = $_init_file_list->( $appname );
   my $cmd = [ $conf->binsdir->catfile( 'notifier-daemon' ), 'get-init-file' ];

   $init->exists or $self->run_cmd( $cmd, { out => $init } );
   $init->is_executable or $init->chmod( oct '0750' );
   $kill->exists or $self->run_cmd( [ 'update-rc.d', $appname, 'defaults' ] );
   return;
};

my $_write_local_config = sub {
   my ($self, $local_conf) = @_;

   my $text = 'The organisation prefix is a two or three character string '
            . 'used by the shortcode generator. If should reflect the name '
            . 'of the group operating the application';

   $self->output( $text, AS_PARA );

   my $prompt = '+Enter the organisation prefix';
   my $prefix = $self->get_line( $prompt, NUL, TRUE, 0 );

   length $prefix > 1 or $prefix = $_random_chars->();
   $prefix = lc substr $prefix, 0, 3;

   my $data = { person_prefix => $prefix, salt => bson64id() };

   $self->file->data_dump( data => $data, path => $local_conf );
   return;
};

my $_write_theme = sub {
   my ($self, $cssd, $file) = @_;

   my $skin = $self->skin;
   my $conf = $self->config;
   my $path = $conf->vardir->catfile( $conf->less, $skin, "${file}.less" );

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
   else { $self->$_write_theme( $cssd, $_ ) for (@{ $conf->themes }) }

   return OK;
}

sub make_skin : method {
   my $self = shift; my $conf = $self->config; my $skin = $self->skin;

   ensure_class_loaded 'Archive::Tar'; my $arc = Archive::Tar->new;

   for my $path ($conf->vardir->catdir( $conf->less, $skin )->all_files) {
      $arc->add_files( $path->abs2rel( $conf->appldir ) );
   }

   for my $path ($conf->template_dir->catdir( $skin )->all_files) {
      $arc->add_files( $path->abs2rel( $conf->appldir ) );
   }

   for my $path ($conf->root->catdir( $conf->images, $skin )->all_files) {
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
   my $localdir = $appldir->catdir( 'local' );

   for my $dir (qw( etc logs run session tmp )) {
      my $path = $localdir->exists ? $localdir->catdir( 'var', $dir )
                                   : $conf->vardir->catdir( $dir );

      $path->exists or $path->mkpath( oct '0770' );
      $dir eq 'etc' and $path->catfile( 'app-notitia.json' )->touch;
   }

   my $local_conf = $conf->home->catfile( 'app-notitia_local.json' );

   $local_conf->exists or $self->$_write_local_config( $local_conf );

   $self->$_create_profile( $localdir );

   my $cmd = $conf->binsdir->catfile( 'notitia-schema' );

   $cmd->exists and $self->$_create_schema( $cmd );

   $EFFECTIVE_USER_ID == 0 and $self->$_root_post_install( $appldir );

   return OK;
}

sub set_sasl_password : method {
   my $self     = shift;
   my $conf     = $self->config;
   my $password = $self->get_line( '+Enter SASL password', AS_PASSWORD );
   my $file     = $conf->ctlfile;
   my $data     = {};

   $file->exists
      and $data = Class::Usul::File->data_load( paths => [ $file ] ) // {};
   $data->{sasl_password} = encrypt_for_config $conf, $password;
   Class::Usul::File->data_dump( { path => $file->assert, data => $data } );

   return OK;
}

sub set_sms_password : method {
   my $self     = shift;
   my $conf     = $self->config;
   my $password = $self->get_line( '+Enter SMS password', AS_PASSWORD );
   my $file     = $conf->ctlfile;
   my $data     = {};

   $file->exists
      and $data = Class::Usul::File->data_load( paths => [ $file ] ) // {};
   $data->{sms_password} = encrypt_for_config $conf, $password;
   Class::Usul::File->data_dump( { path => $file->assert, data => $data } );

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

=head2 C<set_sasl_password> - Set the SASL password

   bin/notitia-cli set-sasl-password

Set the SASL password used to send emails

=head2 C<set_sms_password> - Set the SMS password

   bin/notitia-cli set-sms-password

Set the SMS password used to send bulk text messages

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
