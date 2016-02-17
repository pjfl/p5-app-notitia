use t::boilerplate;

use Test::More;
use English qw( -no_match_vars );

BEGIN {
   $ENV{SCHEMA_TESTING} or plan skip_all => 'Schema test only for developers';
}

use App::Notitia::Schema;
use Class::Usul::Time qw( str2date_time time2str );

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schedule;
my $vehicle_rs =  $schema->resultset( 'Vehicle' );
my $vehicle    =  $vehicle_rs->search( { vrn => 'PJ06KZV' } )->first;
my $date       =  str2date_time time2str '%Y-%m-%d';

my $slot = $vehicle->assign_to_slot( 'main', $date, 'day', 'rider', 0, 'john' );

is $slot->vehicle, 'PJ06KZV', 'Assigns vehicle to slot';

$vehicle  = $vehicle_rs->search( { vrn => 'OU01AAA' } )->first;

my $tport_rs = $schema->resultset( 'Transport' );
my $tport    = $tport_rs->search( { vehicle_id => $vehicle->id } )->first;

$tport and $tport->delete;
$tport =   $vehicle->assign_to_event( 'tinshaking', 'john' );

is $tport, 'OU01AAA', 'Assigns vehicle to event';

eval { $vehicle->assign_to_event( 'tinshaking', 'john' ) }; my $e = $EVAL_ERROR;

like $e, qr{ \Qalready assigned\E }mx, 'Cannot assign vehicle to same event';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
