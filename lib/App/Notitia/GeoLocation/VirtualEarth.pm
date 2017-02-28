package App::Notitia::GeoLocation::VirtualEarth;

use namespace::autoclean;

use Class::Usul::Types    qw( NonEmptySimpleStr );
use Geo::Coordinates::UTM qw( latlon_to_utm );
use Moo;

extends qw( App::Notitia::GeoLocation::Base );

# Public attributes
has 'api_key' => is => 'ro', isa => NonEmptySimpleStr;

has 'base_uri' => is => 'ro', isa => NonEmptySimpleStr,
   default => 'http://dev.virtualearth.net';

has 'uri_template' => is => 'ro', isa => NonEmptySimpleStr,
   default => '%s/REST/v1/Locations?key=%s&o=json&q=';

has '+query_uri' => builder => sub {
   my $self = shift;

   return (sprintf $self->uri_template, $self->base_uri, $self->api_key).'%s';
};

# Private functions
my $_round = sub {
    my $float = shift; return int( $float + $float / abs( $float * 2 ) );
};

my $_convert_to_grid = sub {
   my $coords = shift;

   my ($zone, $x, $y) = latlon_to_utm( 23 , $coords->[ 0 ], $coords->[ 1 ] );

   return sprintf "%d,%d", $_round->( 10 * $x ) / 10, $_round->( 10 * $y ) / 10;
};


# Public methods
around 'locate_by_postcode' => sub {
   my ($orig, $self, $postcode) = @_;

   my $data     = $orig->( $self, $postcode );
   my $src      = $data->{resourceSets}->[ 0 ]->{resources}->[ 0 ];
   my $coords   = $_convert_to_grid->( $src->{point}->{coordinates} );
   my $location = $src->{address}->{locality};

   return { coordinates => $coords, location => $location };
};

1;

__END__

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
