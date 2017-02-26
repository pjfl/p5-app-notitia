package App::Notitia::GeoLocation::VirtualEarth;

use namespace::autoclean;

use Class::Usul::Types qw( NonEmptySimpleStr );
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
my $_convert_to_grid = sub {
   my $coords = shift;

   my $x = int 0.5 + (54593.4200005706 * $coords->[ 0 ] - 2369741.15453625);
   my $y = int 0.5 + (137612.696873342 * $coords->[ 1 ] + 370838.290679448);

   return "${x},${y}";
};

# Public methods
around 'locate_by_postcode' => sub {
   my ($orig, $self, $postcode) = @_;

   my $r        = $orig->( $self, $postcode );
   my $data     = $self->decode_json( $r->{content} );
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
