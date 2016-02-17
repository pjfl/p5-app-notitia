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

eval { $person->delete_endorsement_for( 'speeding' ) };

eval { $person->assert_endorsement_for( 'speeding' ) }; my $e = $EVAL_ERROR;

like $e, qr{ \Qno endorsement\E }mx, 'John has no speeding endorsement';

$person->add_endorsement_for( 'speeding' );

$person = $person_rs->search
   ( { name => 'john' }, { prefetch => 'endorsements' } )->first;

my $endorsement = $person->assert_endorsement_for( 'speeding' );

is $endorsement, 'speeding', 'John has an endorsement for speeding';

eval { $person->add_endorsement_for( 'speeding' ) }; $e = $EVAL_ERROR;

like $e, qr{ \Qalready has endorsement\E }mx,
   'John has a speeding endorsement already';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
