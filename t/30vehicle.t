use t::boilerplate;

use Test::More;
use English qw( -no_match_vars );

use App::Notitia::Schema;

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schedule;
my $vehicle_rs =  $schema->resultset( 'Vehicle' );
my $vehicle    =  $vehicle_rs->search( { vrn => 'PJ06KZV' } )->first;

$vehicle and $vehicle->delete;
$vehicle =   $vehicle_rs->create( { vrn => 'PJ06KZV', type_id => 'bike' } );
$vehicle =   $vehicle_rs->search( { vrn => 'PJ06KZV' } )->first;

is $vehicle, 'PJ06KZV', 'Creates vehicle';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
