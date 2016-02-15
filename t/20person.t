use t::boilerplate;

use Test::More;

use App::Notitia::Schema;

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schedule;
my $person_rs  =  $schema->resultset( 'Person' );
my $person     =  $person_rs->search( { name => 'john' } )->first;

$person and $person->delete;
$person = $person_rs->create( { name => 'john', password => '12345678' } );
$person = $person_rs->search( { name => 'john' } )->first;

is $person->authenticate( '12345678', 1 ), undef, 'Authenticates for update';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
