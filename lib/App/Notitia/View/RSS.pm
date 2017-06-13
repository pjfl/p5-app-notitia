package App::Notitia::View::RSS;

use namespace::autoclean;

use App::Notitia::Util qw( stash_functions );
use Encode             qw( encode );
use English            qw( -no_match_vars );
use Moo;

with q(Web::Components::Role);
with q(Web::Components::Role::TT);

# Public attributes
has '+moniker' => default => 'rss';

# Private functions
my $_header = sub {
   return [ 'Cache-Control' => 'no-store, must-revalidate, max-age=0',
            'Content-Type'  => 'application/rss+xml', @{ $_[ 0 ] // [] } ];
};

my $_template = do { local $RS = undef; <DATA> };

# Public methods
sub serialize {
   my ($self, $req, $stash) = @_; stash_functions $self, $req, $stash;

   $stash->{template}->{layout} = \$_template;

   my $xml = encode( $self->encoding, $self->render_template( $stash ) );

   return [ $stash->{code}, $_header->( $stash->{http_headers} ), [ $xml ] ];
}

1;

=pod

=encoding utf-8

=head1 Name

App::Notitia::View::RSS - People and resource scheduling

=head1 Synopsis

   use App::Notitia::View::RSS;
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

__DATA__
<?xml version="1.0"?>
<rdf:RDF
 xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:content="http://purl.org/rss/1.0/modules/content/"
 xmlns="http://purl.org/rss/1.0/"
>
 <channel rdf:about="[% page.link %]">
  <title>[% page.title | html -%]</title>
  <link>[% page.link %]</link>
  <description>[% page.subtitle | html -%]</description>
  <language>[% page.language %]</language>
  <pubDate>[% page.pubdate %]</pubDate>
  <lastBuildDate>[% page.built %]</lastBuildDate>
  <items>
   <rdf:Seq>
[% FOREACH entry = page.entries -%]
    <rdf:li rdf:resource="[% entry.link %]"/>
[% END -%]
   </rdf:Seq>
  </items>
 </channel>
[% FOREACH entry = page.entries -%]

 <item rdf:about="[% entry.link %]">
  <title>[% entry.title | html -%]</title>
  <link>[% entry.link %]</link>
  <guid isPermaLink="false">[% entry.guid %]</guid>
  <author>[% entry.author %]</author>
[% FOREACH category = entry.categories -%]
  <category>[% category %]</category>
[% END -%]
  <content:encoded>[% entry.content | html -%]</content:encoded>
  <dc:date>[% entry.modified %]</dc:date>
 </item>
[% END -%]
</rdf:RDF>
