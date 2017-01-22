package App::Notitia::View::HTML;

use namespace::autoclean;

use App::Notitia::Util     qw( stash_functions );
use Encode                 qw( encode );
use File::DataClass::Types qw( CodeRef HashRef Object );
use HTML::GenerateUtil     qw( escape_html );
use Web::Components::Util  qw( load_components );
use Moo;

with q(Web::Components::Role);
with q(Web::Components::Role::TT);

# Public attributes
has '+moniker'   => default => 'html';

has 'formatters' => is => 'lazy', isa => HashRef[Object],
   builder       => sub { load_components 'View::HTML', application => $_[0] };

has 'type_map'   => is => 'lazy', isa => HashRef, builder => sub {
   my $self = shift; my $map = { htm => 'html', html => 'html' };

   for my $moniker (keys %{ $self->formatters }) {
      for my $extn (@{ $self->formatters->{ $moniker }->extensions }) {
         $map->{ $extn } = $moniker;
      }
   }

   return $map;
};

# Private functions
my $_header = sub {
   return [ 'Content-Type' => 'text/html', @{ $_[ 0 ] // [] } ];
};

# Public methods
sub serialize {
   my ($self, $req, $stash) = @_; stash_functions $self, $req, $stash;

   my $html = encode( $self->encoding, $self->render_template( $stash ) );

   return [ $stash->{code}, $_header->( $stash->{http_headers} ), [ $html ] ];
}

around 'serialize' => sub {
   my ($orig, $self, $req, $stash) = @_; my $page = $stash->{page} //= {};

   defined $page->{format} or return $orig->( $self, $req, $stash );

   $page->{format} eq 'text'
      and $page->{content} = '<pre>'.escape_html( $page->{content} ).'</pre>'
      and $page->{format } = 'html'
      and return $orig->( $self, $req, $stash );

   my $formatter = $self->formatters->{ $page->{format} };

   $formatter and $page->{content} = $formatter->serialize( $req, $page )
              and $page->{format } = 'html';

   return $orig->( $self, $req, $stash );
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::View::HTML - People and resource scheduling

=head1 Synopsis

   use App::Notitia::View::HTML;
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

Copyright (c) 2017 Peter Flanigan. All rights reserved

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
