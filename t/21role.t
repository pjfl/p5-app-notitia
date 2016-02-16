use t::boilerplate;

use Test::More;
use English qw( -no_match_vars );

BEGIN {
   $ENV{SCHEMA_TESTING} or plan skip_all => 'Schema test only for developers';
}

use App::Notitia::Schema;

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schedule;
my $person_rs  =  $schema->resultset( 'Person' );
my $person     =  $person_rs->search( { name => 'john' } )->first;

eval { $person->delete_member_from( 'bike_rider' ) };
eval { $person->delete_certification_for( 'catagory_b' ) };
eval { $person->add_member_to( 'bike_rider' ) }; my $e = $EVAL_ERROR;

like $e, qr{ \Qno certification\E }mx,
   'Need catagory_b certification to be a bike_rider';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
