use t::boilerplate;

use Test::More;
use English qw( -no_match_vars );

BEGIN {
   $ENV{SCHEMA_TESTING} or plan skip_all => 'Schema test only for developers';
}

use App::Notitia::Schema;

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schema;
my $person_rs  =  $schema->resultset( 'Person' );
my $person     =  $person_rs->search( { name => 'john' } )->first;

eval { $person->delete_member_from( 'rider' ) };

eval { $person->assert_member_of( 'rider' ) }; my $e = $EVAL_ERROR;

like $e, qr{ \Qnot a member\E }mx, 'John is not a rider';

$person->add_member_to( 'rider' );

$person = $person_rs->search
   ( { name => 'john' }, { prefetch => 'roles' } )->first;

my $role = $person->assert_member_of( 'rider' );

is $role, 'rider', 'John is now a rider';

eval { $person->add_member_to( 'rider' ) }; $e = $EVAL_ERROR;

like $e, qr{ \Qalready a member\E }mx, 'John is already a rider';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
