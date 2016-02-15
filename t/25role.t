use t::boilerplate;

use Test::More;
use English qw( -no_match_vars );

use App::Notitia::Schema;

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schedule;
my $person_rs  =  $schema->resultset( 'Person' );
my $person     =  $person_rs->search( { name => 'john' } )->single;

eval { $person->delete_member_from( 'bike_rider' ) };

$person->add_member_to( 'bike_rider' );

$person = $person_rs->search
   ( { name => 'john' }, { prefetch => 'roles' } )->first;

is $person->roles->first->type->name, 'bike_rider', 'John is a bike rider';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
