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
my $event_rs   =  $schema->resultset( 'Event' );
my $event      =  $event_rs->search( { name => 'tinshaking' } )->first;
my $date       =  str2date_time time2str '%Y-%m-%d';

$event and $event_rs->delete;
$event =   $event_rs->create
   ( { name => 'tinshaking', rota => 'main', date => $date, owner => 'john' } );
$event =   $event_rs->search( { name => 'tinshaking' } )->first;

is $event, 'tinshaking', 'Creates event';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
