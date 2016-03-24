use t::boilerplate;

use Test::More;

use_ok 'App::Notitia';

use App::Notitia::Util qw( lcm_for );

is lcm_for( 2, 3, 4, 4 ), 12, 'lcm 2344';
is lcm_for( 4, 3, 4, 4 ), 12, 'lcm 4344';
is lcm_for( 2, 4, 5, 5 ), 20, 'lcm 2455';
is lcm_for( 2, 3, 5, 5 ), 30, 'lcm 2355';
is lcm_for( 4, 3, 5, 5 ), 60, 'lcm 4355';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
