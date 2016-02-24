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
my $schema     =  $connection->schema;
my $person_rs  =  $schema->resultset( 'Person' );
my $person     =  $person_rs->search( { name => 'john' } )->first;
my $date       =  str2date_time time2str '%Y-%m-%d';
my $slot_rs    =  $schema->resultset( 'Slot' );
my $slot       =  $slot_rs->search( { operator_id => $person->id } )->first;

$slot and $slot->delete;
$slot =   $person->claim_slot( 'main', $date, 'day', 'rider', 0, 1 );

like $slot, qr{ \A main_ [0-9\-]+ _day_rider_0 \z }mx, 'Claims slot';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
