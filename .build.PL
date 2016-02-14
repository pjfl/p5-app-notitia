use strict;
use warnings;

use Module::Build ##{ $meta2{prereqs}->{configure}->{requires}->{'Module::Build'} ##};

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

Module::Build->new(
   'module_name' => $name,
   'notes'       => { min_perl_version => $perl_ver, testing => $testing->() },
   %{ $prereqs },
##{ $plugin->get_default('share_dir') ##}
)->create_build_script;

exit 0;
