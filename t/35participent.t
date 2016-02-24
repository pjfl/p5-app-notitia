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

eval { $person->delete_participent_for( 'tinshaking' ) };

eval { $person->assert_participent_for( 'tinshaking' ) }; my $e = $EVAL_ERROR;

like $e, qr{ \Qnot participating\E }mx,
   'John is not participating in tinshaking';

$person->add_participent_for( 'tinshaking' );

$person = $person_rs->search
   ( { name => 'john' }, { prefetch => 'participents' } )->first;

my $participent = $person->assert_participent_for( 'tinshaking' );

is $participent, 'tinshaking', 'John is participating in tinshaking';

eval { $person->add_participent_for( 'tinshaking' ) }; $e = $EVAL_ERROR;

like $e, qr{ \Qalready participating\E }mx,
   'John is already participating in tinshaking';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
