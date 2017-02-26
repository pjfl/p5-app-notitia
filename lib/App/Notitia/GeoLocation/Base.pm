package App::Notitia::GeoLocation::Base;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Time       qw( nap );
use Class::Usul::Types      qw( HashRef NonEmptySimpleStr PositiveInt );
use HTTP::Tiny;
use JSON::MaybeXS           qw( );
use Unexpected::Functions   qw( Unspecified );
use Moo;

# Public attributes
has 'http_options' => is => 'ro',   isa => HashRef, builder => sub { {} };

has 'num_tries'    => is => 'ro',   isa => PositiveInt, default => 3;

has 'timeout'      => is => 'ro',   isa => PositiveInt, default => 10;

has 'query_uri'    => is => 'lazy', isa => NonEmptySimpleStr;

# Public methods
sub assert_lookup_success {
   my ($self, $res) = @_;

   $self->is_success( $res ) or throw
      'Geolocation lookup error [_1]: [_2]', [ $res->{status}, $res->{reason} ];

   return;
}

sub decode_response {
   return JSON::MaybeXS->new( utf8 => FALSE )->decode( $_[ 1 ]->{content} );
}

sub is_success {
   return $_[ 1 ]->{success} ? TRUE : FALSE;
}

sub locate_by_postcode {
   my ($self, $postcode) = @_; $postcode //= NUL;

   $postcode =~ s{ [ ] }{}gmx; $postcode or throw Unspecified, [ 'postcode' ];

   my $uri  = sprintf $self->query_uri, uc $postcode;
   my $attr = { %{ $self->http_options }, timeout => $self->timeout };
   my $http = HTTP::Tiny->new( %{ $attr } );
   my $res;

   for (1 .. $self->num_tries) {
      $res = $http->get( $uri ); $self->is_success( $res ) and last; nap 0.25;
   }

   $self->assert_lookup_success( $res );

   return $self->decode_response( $res );
}

1;

__END__
