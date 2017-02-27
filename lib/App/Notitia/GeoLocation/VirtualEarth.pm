package App::Notitia::GeoLocation::VirtualEarth;

use namespace::autoclean;
use POSIX qw( floor pow abs );
use Math::Trig;
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
my $_round = sub {
    my $float = shift;
    return int($float + $float/abs($float*2));
};

my $_convert_to_grid = sub {
        my $coords = shift;

        my ($latd, $lngd) = ( $coords->[ 0 ], $coords->[ 1 ] );

	my $a    = 6378137.0;
	my $f    = 1/298.2572236;
	my $drad = 3.1415926/180;
	my $k0   = 0.9996;
	my $b    = $a*(1-$f);
	my $e    = sqrt(1 - ($b/$a)*($b/$a));

        $latd < -90  or $latd > 90  and die "Latitude must be between -90 and 90";
	$lngd < -180 or $lngd > 180 and die "Latitude must be between -180 and 180";

        my $ydd = floor(abs($latd));
        my $xdd = floor(abs($lngd));
 
        $latd < 0 and $ydd -= $ydd;
        $lngd < 0 and $xdd -= $xdd;
	
	my $phi  = $latd*$drad;
	my $utmz = 1 + floor(($lngd+180)/6);
	my $latz = 0;

	$latd > -80 and $latd < 72 and $latz = floor(($latd + 80)/8)+2;
	$latd > 72  and $latd < 84 and $latz = 21;
	$latd > 84  and $latz = 23;
		
	my $zcm  = 3 + 6*($utmz-1) - 180;
	my $esq  = (1 - ($b/$a)*($b/$a));
	my $e0sq = $e*$e/(1-$e*$e);
	my $N    = $a/sqrt(1-pow($e*sin($phi),2));
	my $T    = pow(tan($phi),2);
	my $C    = $e0sq*pow(cos($phi),2);
	my $A    = ($lngd-$zcm)*$drad*cos($phi);

	my $M = $phi*(1 - $esq*(1/4 + $esq*(3/64 + 5*$esq/256)));
	$M = $M - sin(2*$phi)*($esq*(3/8 + $esq*(3/32 + 45*$esq/1024)));
	$M = $M + sin(4*$phi)*($esq*$esq*(15/256 + $esq*45/1024));
	$M = $M - sin(6*$phi)*($esq*$esq*$esq*(35/3072));
	$M = $M*$a;

	my $x  = $k0*$N*$A*(1 + $A*$A*((1-$T+$C)/6 + $A*$A*(5 - 18*$T + $T*$T + 72*$C -58*$e0sq)/120)) + 500000;
	my $y  = $k0*($M + $N*tan($phi)*($A*$A*(1/2 + $A*$A*((5 - $T + 9*$C + 4*$C*$C)/24 + $A*$A*(61 - 58*$T + $T*$T + 600*$C - 330*$e0sq)/720))));

 	$y < 0 and $y += 10000000;

        return sprintf "%d,%d", $_round->(10*($x))/10, $_round->(10*$y)/10;
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
