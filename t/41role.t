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

eval { $person->delete_member_from( 'asset_manager' ) };

$person->add_member_to( 'asset_manager' );

$person = $person_rs->search
   ( { name => 'john' }, { prefetch => 'roles' } )->first;

my $role = $person->assert_member_of( 'asset_manager' );

is $role, 'asset_manager', 'John is now an asset manager';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
