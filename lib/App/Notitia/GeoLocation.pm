package App::Notitia::GeoLocation;

use namespace::autoclean;

use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( throw );
use Class::Usul::Time      qw( nap );
use Class::Usul::Types     qw( HashRef Logger NonEmptySimpleStr PositiveInt );
use HTTP::Tiny;
use JSON::MaybeXS;
use Moo;

# Public attributes
has 'base_uri'     => is => 'ro',   isa => NonEmptySimpleStr,
   default         => 'http://www.uk-postcodes.com';

has 'http_options' => is => 'ro',   isa => HashRef, builder => sub { {} };

has 'log'          => is => 'ro',   isa => Logger,
   builder         => sub { Class::Null->new };

has 'num_tries'    => is => 'ro',   isa => PositiveInt, default => 3;

has 'timeout'      => is => 'ro',   isa => PositiveInt, default => 10;

has 'uri_template' => is => 'ro',   isa => NonEmptySimpleStr,
   default         => '%s/postcode/%s.json';

# Public methods
sub find_by_postcode {
   my ($self, $postcode, $opts) = @_; $opts //= {};

   my $res; $postcode =~ s{ [ ] }{}gmx;
   my $uri  = sprintf $self->uri_template, $self->base_uri, uc $postcode;
   my $attr = { %{ $self->http_options } }; $attr->{timeout} ||= $self->timeout;
   my $http = HTTP::Tiny->new( %{ $attr } );

   for (1 .. $self->num_tries) {
      $res = $http->get( $uri ); $res->{success} and last; nap 0.25;
   }

   $res->{success} or throw
      'Postcode lookup error [_1]: [_2]', [ $res->{status}, $res->{reason} ];

   my $json_coder = JSON::MaybeXS->new( utf8 => FALSE );
   my $data = $json_coder->decode( $res->{content} );

   $opts->{raw} and return $data;

   my $parish = $data->{administrative}->{parish}->{title};
   my $coords = $data->{geo}->{easting} && $data->{geo}->{northing}
              ? $data->{geo}->{easting}.','.$data->{geo}->{northing} : undef;

   return { coordinates => $coords, location => $parish, };
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::GeoLocation - People and resource scheduling

=head1 Synopsis

   use App::Notitia::GeoLocation;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head1 Diagnostics

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Notitia.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2016 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
