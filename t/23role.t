use t::boilerplate;

use Test::More;
use English qw( -no_match_vars );

BEGIN {
   $ENV{SCHEMA_TESTING} or plan skip_all => 'POD test only for developers';
}

use App::Notitia::Schema;

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schedule;
my $person_rs  =  $schema->resultset( 'Person' );
my $person     =  $person_rs->search( { name => 'john' } )->first;

eval { $person->delete_member_from( 'bike_rider' ) };

eval { $person->assert_member_of( 'bike_rider' ) }; my $e = $EVAL_ERROR;

like $e, qr{ \Qnot member\E }mx, 'John is not a bike rider';

$person->add_member_to( 'bike_rider' );

$person = $person_rs->search
   ( { name => 'john' }, { prefetch => 'roles' } )->first;

my $role = $person->assert_member_of( 'bike_rider' );

is $role, 'bike_rider', 'John is a bike rider';

eval { $person->add_member_to( 'bike_rider' ) }; $e = $EVAL_ERROR;

like $e, qr{ \Qalready a member\E }mx, 'John is a bike rider already';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
