# Build.PL is generated - do not edit
use strict;
use warnings;

use Module::Build 0.4004;
use File::Spec::Functions qw( catdir );

my $perl_ver = 5.010001;
my $name     = 'App-Notitia'; $name =~ s{ - }{::}gmx;
my $prereqs  = {
  'build_requires' => {
    'Module::Build' => '0.4004',
    'version' => '0.88'
  },
  'configure_requires' => {
    'Module::Build' => '0.4004',
    'version' => '0.88'
  },
  'recommends' => {
    'CSS::LESS' => 'v0.0.3'
  },
  'requires' => {
    'App::Ack' => '2.12',
    'Auth::GoogleAuth' => '1.01',
    'Authen::SASL' => '2.16',
    'Class::Null' => '2.110730',
    'Class::Usul' => 'v0.82.0',
    'Cpanel::JSON::XS' => '3.0115',
    'Crypt::Eksblowfish' => '0.009',
    'DBIx::Class' => '0.08204',
    'DBIx::Class::InflateColumn::Object::Enum' => '0.04',
    'DBIx::Class::TimeStamp' => '0.14',
    'Daemon::Control' => '0.001006',
    'Data::Page' => '2.02',
    'Data::Record' => '0.02',
    'Data::Validation' => 'v0.28.0',
    'DateTime' => '1.19',
    'Email::MIME' => '1.934',
    'Email::Sender' => '1.300018',
    'Exporter::Tiny' => '0.042',
    'FCGI' => '0.77',
    'FCGI::ProcManager' => '0.25',
    'File::DataClass' => 'v0.69.0',
    'Format::Human::Bytes' => '0.06',
    'Geo::Coordinates::UTM' => '0.11',
    'Graphics::ColorNames' => '2.11',
    'HTML::GenerateUtil' => '1.20',
    'HTTP::Message' => '6.06',
    'IO::String' => '1.08',
    'JSON::MaybeXS' => '1.003005',
    'List::SomeUtils' => '0.53',
    'List::Util' => '1.42',
    'MIME::Base64' => '3.13',
    'MIME::Types' => '2.11',
    'Moo' => '2.000001',
    'Plack' => '1.0036',
    'Plack::Middleware::Debug' => '0.16',
    'Plack::Middleware::Deflater' => '0.08',
    'Plack::Middleware::FixMissingBodyInRedirect' => '0.12',
    'Plack::Middleware::LogErrors' => '0.001',
    'Plack::Middleware::Options' => '0.01',
    'Plack::Middleware::ReverseProxy' => '0.15',
    'Plack::Middleware::Session' => '0.21',
    'Starman' => '0.4014',
    'Text::CSV' => '1.33',
    'Text::MultiMarkdown' => '1.000035',
    'Try::Tiny' => '0.22',
    'Type::Tiny' => '1.000005',
    'Unexpected' => 'v0.46.0',
    'Web::Components' => 'v0.8.0',
    'Web::Components::Role::Email' => 'v0.2.0',
    'Web::Components::Role::TT' => 'v0.7.0',
    'Web::ComposableRequest' => 'v0.19.0',
    'Web::Simple' => '0.030',
    'YAML::Tiny' => '1.67',
    'local::lib' => '2.000015',
    'namespace::autoclean' => '0.26',
    'perl' => '5.010001',
    'strictures' => '2.000000'
  },
  'test_requires' => {
    'File::Spec' => '0',
    'Module::Build' => '0.4004',
    'Module::Metadata' => '0',
    'Sys::Hostname' => '0',
    'Test::Requires' => '0.06',
    'version' => '0.88'
  },
};
my $testing  = sub { $ENV{AUTOMATED_TESTING}
                  || $ENV{PERL_CPAN_REPORTER_CONFIG}
                  || $ENV{PERL5_CPANPLUS_IS_VERSION} };
my $whimper  = sub { print {*STDOUT} $_[ 0 ]."\n"; exit 0 };
my $stop     = sub {
   $testing->() or $whimper->( $_[ 0 ] );
   $prereqs->{build_requires} = { %{ $prereqs->{configure_requires} } };
   $prereqs->{test_requires } = { %{ $prereqs->{configure_requires} } };
   $prereqs->{test_requires }->{ 'Test::Requires' } = 0.06;
   delete $prereqs->{requires};
};

# Not interested in reports below min perl ver
$] < $perl_ver and $stop->( "Minimum required Perl version is ${perl_ver}" );

my $bob = Module::Build->subclass( code => do { local $/; <DATA> } )->new(
   'add_to_cleanup' => [ 'debian', 'META.yml' ],
   'module_name'    => $name,
   'notes'          => { min_perl_version => $perl_ver,
                         testing          => $testing->() },
   %{ $prereqs },

);

$bob->install_path( 'bin'    => catdir( $bob->install_base, 'bin'   ) );
$bob->install_path( 'lib'    => catdir( $bob->install_base, 'lib'   ) );
$bob->install_path( 'var'    => catdir( $bob->install_base, 'var'   ) );
$bob->install_path( 'local'  => catdir( $bob->install_base, 'local' ) );
$bob->install_path( 'script' => catdir( $bob->install_base, 'bin'   ) );
$bob->install_path( 'bindoc' => catdir( $bob->install_base, 'man', 'man1' ) );
$bob->install_path( 'libdoc' => catdir( $bob->install_base, 'man', 'man3' ) );
$bob->add_build_element( 'changes' );
$bob->add_build_element( 'config'  );
$bob->add_build_element( 'local'   );
$bob->add_build_element( 'var'     );
$bob->create_build_script;
exit 0;

__DATA__

use File::Basename        qw( dirname );
use File::Copy            qw( copy );
use File::Find            qw( find );
use File::Path            qw( make_path );
use File::Spec::Functions qw( catdir catfile );

sub _added_to_INC { # CVE-2016-1238
  my $self = shift; my %seen;

  for ($self->_default_INC) { $seen{ $_ }++ }

  return grep { not $seen{ $_ }++ } $self->base_dir, @INC;
}

sub ACTION_install {
   my $self = shift; umask oct '0007'; $self->SUPER::ACTION_install();

   for my $dir (qw( etc logs run session tmp )) {
      my $path = catdir( $self->install_path( 'var' ), $dir );

      $self->destdir and $path = catdir( $self->destdir, $path );
      -d $path or make_path( $path, { mode => oct '0770' } );
   }

   return;
}

sub process_changes_files {
   return $_[ 0 ]->_process_files( 'Changes', catdir( 'blib', 'var', 'etc' ) );
}

sub process_config_files {
   my $self     = shift; umask oct '0027';
   my $distname = $self->dist_name;
   my $home     = catdir( 'lib', split m{ - }mx, $distname);

   return $self->_process_files( catfile( $home, (lc $distname).'.json' ) );
}

sub process_local_files {
   my $self = shift; return $self->_process_files( 'local' );
}

sub process_var_files {
   my $self = shift; my $pattern; umask oct '0027';

   for (qw( .git logs run tmp )) {
      $pattern .= ($pattern ? '|' : q()).(catdir( q(), $_ ));
   }

   $self->_skip_pattern( qr{ (?: $pattern ) }mx );
   return $self->_process_files( 'var' );
}

sub _process_files {
   # Find and copy files and directories from source tree to destination tree
   my ($self, $src, $dest) = @_; $src or return; $dest ||= 'blib';

   if    (-f $src) { $self->_copy_file( $src, $dest ) }
   elsif (-d $src) {
      my $prefix = $self->base_dir;

      find( { no_chdir => TRUE, wanted => sub {
         (my $path = $File::Find::name) =~ s{ \A $prefix }{}mx;
         return $self->_copy_file( $path, $dest );
      }, }, $src );
   }

   return;
}

sub _copy_file {
   my ($self, $src, $dest) = @_; my $pattern = $self->_skip_pattern;

   ($src and -f $src and (not $pattern or $src !~ $pattern)) or return;
   # Rebase the directory path
   my $dir = catdir( $dest, dirname( $src ) );
   # Ensure target directory exists
   -d $dir or make_path( $dir, { mode => oct '0750' } );
   copy( $src, $dir );
   return;
}

sub _skip_pattern { # Accessor/mutator for the regex of paths not to process
   return defined $_[ 1 ] ? $_[ 0 ]->{_skip_pattern} = $_[ 1 ]
                          : $_[ 0 ]->{_skip_pattern};
}
