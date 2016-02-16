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

eval { $person->delete_certification_for( 'catagory_b' ) };

eval { $person->assert_certification_for( 'catagory_b' ) }; my $e = $EVAL_ERROR;

like $e, qr{ \Qno certification\E }mx, 'John has no catagory_b certification';

$person->add_certification_for( 'catagory_b' );

$person = $person_rs->search
   ( { name => 'john' }, { prefetch => 'certs' } )->first;

my $certification = $person->assert_certification_for( 'catagory_b' );

is $certification, 'catagory_b', 'John has catagory_b certification';

eval { $person->add_certification_for( 'catagory_b' ) }; $e = $EVAL_ERROR;

like $e, qr{ \Qalready has certification\E }mx,
   'John has catagory_b certification already';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
