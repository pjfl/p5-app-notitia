package App::Notitia::GeoLocation::Base;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Time       qw( nap );
use Class::Usul::Types      qw( HashRef NonEmptySimpleStr PositiveInt );
use HTTP::Tiny;
use JSON::MaybeXS;
use Unexpected::Functions   qw( Unspecified );
use Moo;

# Public attributes
has 'base_uri'     => is => 'lazy', isa => NonEmptySimpleStr;

has 'http_options' => is => 'ro',   isa => HashRef, builder => sub { {} };

has 'num_tries'    => is => 'ro',   isa => PositiveInt, default => 3;

has 'timeout'      => is => 'ro',   isa => PositiveInt, default => 10;

has 'uri_template' => is => 'lazy', isa => NonEmptySimpleStr;

# Public methods
sub find_by_postcode {
   my ($self, $postcode, $opts) = @_; $postcode //= NUL; $opts //= {};

   $postcode =~ s{ [ ] }{}gmx; $postcode or throw Unspecified, [ 'postcode' ];

   my $uri  = sprintf $self->uri_template, uc $postcode;
   my $attr = { %{ $self->http_options }, timeout => $self->timeout };
   my $http = HTTP::Tiny->new( %{ $attr } );
   my $res;

   for (1 .. $self->num_tries) {
      $res = $http->get( $uri ); $res->{success} and last; nap 0.25;
   }

   $res->{success} or throw
      'Postcode lookup error [_1]: [_2]', [ $res->{status}, $res->{reason} ];

   my $json_coder = JSON::MaybeXS->new( utf8 => FALSE );

   return $json_coder->decode( $res->{content} );
}

1;

__END__
