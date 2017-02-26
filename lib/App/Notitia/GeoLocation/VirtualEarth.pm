package App::Notitia::GeoLocation::VirtualEarth;

use namespace::autoclean;

use Class::Usul::Types qw( NonEmptySimpleStr );
use Moo;

extends qw( App::Notitia::GeoLocation::Base );

has '+base_uri' => default => 'http://dev.virtualearth.net';

has '+uri_template' => builder => sub {
   return (sprintf '%s/REST/v1/Locations?key=%s&o=json&q=',
           $_[ 0 ]->base_uri, $_[ 0 ]->api_key).'%s' };

has 'api_key' => is => 'ro', isa => NonEmptySimpleStr;

# Public methods
around 'find_by_postcode' => sub {
   my ($orig, $self, $postcode, $opts) = @_;

   my $r = $orig->( $self, $postcode, $opts ); $opts->{raw} and return $r;

   my $src = $r->{resourceSets}->[ 0 ]->{resources}->[ 0 ];
   my $points = $src->{point}->{coordinates};

   my $x = int 0.5 + (54593.4200005706 * $points->[ 0 ] - 2369741.15453625);
   my $y = int 0.5 + (137612.696873342 * $points->[ 1 ] + 370838.290679448);

   my $coords = "${x},${y}"; my $parish = $src->{address}->{locality};

   return { coordinates => $coords, location => $parish, };
};

1;

__END__

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
