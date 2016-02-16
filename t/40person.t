use t::boilerplate;

use Test::More;
use English qw( -no_match_vars );

BEGIN {
   $ENV{SCHEMA_TESTING} or plan skip_all => 'POD test only for developers';
}

use App::Notitia::Schema;
use Class::Usul::Time qw( str2date_time time2str );

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schedule;
my $person_rs  =  $schema->resultset( 'Person' );
my $person     =  $person_rs->search( { name => 'john' } )->first;
my $date       =  str2date_time time2str '%Y-%m-%d';

$person->claim_slot( 'main', $date, 'day', 'rider', 0, 1 );

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
