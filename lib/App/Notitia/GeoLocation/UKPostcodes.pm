package App::Notitia::GeoLocation::UKPostcodes;

use namespace::autoclean;

use Class::Usul::Types qw( NonEmptySimpleStr );
use Moo;

extends qw( App::Notitia::GeoLocation::Base );

# Public attributes
has 'base_uri' => is => 'ro', isa => NonEmptySimpleStr,
   default => 'http://www.uk-postcodes.com';

has 'uri_template' => is => 'ro', isa => NonEmptySimpleStr,
   default => '%s/postcode/';

has '+query_uri' => builder => sub {
   return (sprintf $_[ 0 ]->uri_template, $_[ 0 ]->base_uri).'%s.json';
};

# Public methods
around 'locate_by_postcode' => sub {
   my ($orig, $self, $postcode) = @_;

   my $r        = $orig->( $self, $postcode );
   my $data     = $self->decode_json( $r->{content} );
   my $coords   = $data->{geo}->{easting} && $data->{geo}->{northing}
                ? $data->{geo}->{easting}.','.$data->{geo}->{northing} : undef;
   my $location = $data->{administrative}->{parish}->{title};

   return { coordinates => $coords, location => $location };
};

1;

__END__

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
