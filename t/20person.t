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
my $e;

$person and $person->delete;
$person = eval { $person_rs->create
                    ( { email_address => 'john@ex.com', first_name => 'john',
                        last_name => 'smith', name => 'john',
                        password => '12345678' } ) };

if ($e = $EVAL_ERROR) {
   if ($e->can( 'class' ) and $e->class eq 'ValidationErrors') {
      warn "${_}\n" for (@{ $e->args });
      exit 1;
   }
   else { die $e }
}

$person = $person_rs->search( { name => 'john' } )->first;

eval { $person->authenticate( '12345678' ) }; $e = $EVAL_ERROR;

is $e->class, 'AccountInactive', 'Inactive account throws on authentication';

eval { $person->activate };

if ($e = $EVAL_ERROR) {
   if ($e->can( 'class' ) and $e->class eq 'ValidationErrors') {
      warn "${_}\n" for (@{ $e->args });
      exit 1;
   }
   else { die $e }
}

eval { $person->authenticate( '12345678' ) }; $e = $EVAL_ERROR;

is $e->class, 'PasswordExpired', 'Password expired throws on authentication';

$person->set_password( '12345678', 'abcdefgh' );

is $person->authenticate( 'abcdefgh' ), undef, 'Authenticates if password set';

eval { $person->authenticate( 'nonono' ) }; $e = $EVAL_ERROR;

is $e->class, 'IncorrectPassword', 'Authenticate throws on incorrect password';

eval { $person_rs->create
          ( { email_address => 'john@ex.com', first_name => 'a',
              last_name  => 'user', name => 'x', password => '12345678' } ) };

$e = $EVAL_ERROR; is $e->class, 'ValidationErrors', 'Validation errors';

is $e->args->[ 0 ]->class, 'ValidLength', 'Invalid name length';

$person =   $person_rs->search( { name => 'admin' } )->first;
$person and $person->delete;
$person =   $person_rs->create
   ( { email_address => 'admin@example.com',
       first_name => 'Admin', last_name => 'User',
       name       => 'admin', password  => '12345678' } );
$person->activate;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
