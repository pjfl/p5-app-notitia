package App::Notitia::GeoLocation::UKPostcodes;

use namespace::autoclean;

use Moo;

extends qw( App::Notitia::GeoLocation::Base );

has '+base_uri' => default => 'http://www.uk-postcodes.com';

has '+uri_template' => builder => sub {
   (sprintf '%s/postcode/', $_[ 0 ]->base_uri).'%s.json' };

# Public methods
around 'find_by_postcode' => sub {
   my ($orig, $self, $postcode, $opts) = @_;

   my $r = $orig->( $self, $postcode, $opts ); $opts->{raw} and return $r;

   my $parish = $r->{administrative}->{parish}->{title};
   my $coords = $r->{geo}->{easting} && $r->{geo}->{northing}
              ? $r->{geo}->{easting}.','.$r->{geo}->{northing} : undef;

   return { coordinates => $coords, location => $parish, };
};

1;

__END__

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
