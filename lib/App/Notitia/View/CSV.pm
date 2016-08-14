package App::Notitia::View::CSV;

use namespace::autoclean;

use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( is_hashref );
use Class::Usul::Types     qw( Object );
use Encode                 qw( encode );
use Text::CSV;
use Moo;

with q(Web::Components::Role);

# Public attributes
has '+moniker' => default => 'csv';

# Private attributes
has '_transcoder' => is => 'lazy', isa => Object,
   builder        => sub { Text::CSV->new( { binary => TRUE } ) };

# Private functions
my $_deref = sub {
   my $col = shift; my $v = $col->{value};

   is_hashref $v and $v->{type} eq 'link' and return $v->{value};

   return $v;
};

my $_header = sub {
   return [ 'Content-Type' => 'text/csv', @{ $_[ 0 ] // [] } ];
};

# Public methods
sub serialize {
   my ($self, $req, $stash) = @_; my $text;

   my $coder = $self->_transcoder; my $content = $stash->{page}->{content};

   for my $row ($content->{headers}, @{ $content->{rows} }) {
      my $status = $coder->combine( map { $_deref->( $_ ) } @{ $row } );

      $text .= $coder->string."\n";
   }

   $content = encode( $self->encoding, $text );

   return [ $stash->{code}, $_header->( $stash->{http_headers} ), [ $content ]];
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::View::CSV - People and resource scheduling

=head1 Synopsis

   use App::Notitia::View::CSV;
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
