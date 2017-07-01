# Build.PL is generated - do not edit
use strict;
use warnings;

use Module::Build ##{ $meta2{prereqs}->{configure}->{requires}->{'Module::Build'} ##};
use File::Spec::Functions qw( catdir );

my $perl_ver = ##{ $meta2{prereqs}->{runtime}->{requires}->{perl} ##};
my $name     = '##{ $zilla->name ##}'; $name =~ s{ - }{::}gmx;
my $prereqs  = {
##{ $plugin->get_prereqs( 1 ) ##}
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
   'module_name' => $name,
   'notes' => { min_perl_version => $perl_ver, testing => $testing->(), },
   %{ $prereqs },
##{ $plugin->get_default('share_dir') ##}
);

$bob->install_path( 'bin'    => catdir( $bob->install_base, 'bin'   ) );
$bob->install_path( 'lib'    => catdir( $bob->install_base, 'lib'   ) );
$bob->install_path( 'var'    => catdir( $bob->install_base, 'var'   ) );
$bob->install_path( 'local'  => catdir( $bob->install_base, 'local' ) );
$bob->install_path( 'script' => catdir( $bob->install_base, 'bin'   ) );
$bob->install_path( 'bindoc' => catdir( $bob->install_base, 'man', 'man1' ) );
$bob->install_path( 'libdoc' => catdir( $bob->install_base, 'man', 'man3' ) );
$bob->add_build_element( 'changes'  );
$bob->add_build_element( 'config'   );
$bob->add_build_element( 'local'    );
$bob->add_build_element( 'template' );
$bob->add_build_element( 'var'      );
$bob->create_build_script;
exit 0;

__DATA__

use Data::Dumper;
use Digest::MD5           qw( md5_hex );
use English               qw( -no_match_vars );
use File::Basename        qw( basename dirname );
use File::Copy            qw( copy );
use File::Find            qw( find );
use File::Path            qw( make_path );
use File::Spec::Functions qw( catdir catfile );

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
   my $self = shift; $self->_skip_pattern( q() ); umask oct '0027';

   return $self->_process_files( 'Changes', catdir( 'blib', 'var', 'etc' ) );
}

sub process_config_files {
   my $self     = shift; $self->_skip_pattern( q() ); umask oct '0027';
   my $distname = $self->dist_name;
   my $home     = catdir( 'lib', split m{ - }mx, $distname);

   return $self->_process_files( catfile( $home, (lc $distname).'.json' ) );
}

sub process_local_files {
   my $self = shift; $self->_skip_pattern( q() ); umask oct '0027';

   return $self->_process_files( 'local' );
}

sub process_template_files {
   my $self   = shift; $self->_skip_pattern( q() ); umask oct '0007';
   my $dest   = catdir( $self->install_path( 'var' ), 'templates', 'emails' );
   my $src    = catdir( 'var', 'templates', 'emails' );
   my $prefix = $self->base_dir;

   find( { no_chdir => 1, wanted => sub {
      (my $from = $File::Find::name) =~ s{ \A $prefix }{}mx;

      $from eq $src and return;

      my $file   = basename( $from );
      my $target = catfile( $dest, $file );
      my $c_csum; -e $target and $c_csum = _cached_csum( $dest, $file );

      if (not $c_csum or $c_csum eq _get_csum( $target )) {
         $self->_copy_file( $from, 'blib' );
         _cached_csum( $dest, $file, _get_csum( $from ) );
      }

      return;
   }, }, $src );

   return;
}

sub process_var_files {
   my $self = shift; my $pattern;

   for (qw( \.git templates/emails logs run tmp )) {
      $pattern .= ($pattern ? '|' : q()).(catdir( q(), $_ ));
   }

   $self->_skip_pattern( qr{ (?: $pattern ) }mx ); umask oct '0027';

   return $self->_process_files( 'var' );
}

sub _added_to_INC { # CVE-2016-1238
  my $self = shift; my %seen;

  for ($self->_default_INC) { $seen{ $_ }++ }

  return grep { not $seen{ $_ }++ } $self->base_dir, @INC;
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

my $_csums_cache;

sub _cached_csum {
   my ($dir, $file, $v) = @_;

   my $csums = catfile( $dir, '.csums' );

   defined $_csums_cache or $_csums_cache = -e $csums ? do $csums : {};

   defined $v or return $_csums_cache->{ $file };

   $_csums_cache->{ $file } = $v; -e $dir or return $v;

   my $dumper = Data::Dumper->new( [ $_csums_cache ], [ 'x' ] );
   my $dumped = $dumper->Purity( 1 )->Sortkeys( 1 )->Terse( 0 )->Dump();

   open my $fh, '>', $csums or die "Path ${csums} cannot open: ${OS_ERROR}";

   print {$fh} $dumped; close $fh;

   return $v;
}

sub _get_csum {
   my $path = shift;

   open my $in, '<', $path or die "Path ${path} cannot open: ${OS_ERROR}";

   my $content; { local $RS = undef; $content = <$in> }; close $in;

   return defined $content ? md5_hex( $content ) : q();
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

sub _skip_pattern { # Accessor/mutator for the regex of paths not to process
   return defined $_[ 1 ] ? $_[ 0 ]->{_skip_pattern} = $_[ 1 ]
                          : $_[ 0 ]->{_skip_pattern};
}
