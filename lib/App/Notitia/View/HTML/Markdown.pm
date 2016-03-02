package App::Notitia::View::HTML::Markdown;

use namespace::autoclean;

use App::Notitia::Markdown;
use Class::Usul::Types qw( ArrayRef Object );
use Scalar::Util       qw( blessed );
use Moo;

with q(Web::Components::Role);

# Public attributes
has '+moniker'   => default => 'markdown';

has 'extensions' => is => 'lazy', isa => ArrayRef,
   builder       => sub { $_[ 0 ]->config->extensions->{markdown} };

has 'formatter'  => is => 'lazy', isa => Object, builder => sub {
   App::Notitia::Markdown->new( tab_width => $_[ 0 ]->config->mdn_tab_width ) };

# Public methods
sub serialize {
   my ($self, $req, $page) = @_; my $content = $page->{content};

   my $markdown = blessed $content ? $content->all : $content;

   $page->{editing} and return $markdown;

   $markdown =~ s{ \A --- $ ( .* ) ^ --- $ }{}msx;

   $page->{filter} and $markdown = $page->{filter}->( $self, $markdown );

   return $self->formatter->markdown( $markdown );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::View::HTML::Markdown - People and resource scheduling

=head1 Synopsis

   use App::Notitia::View::HTML::Markdown;
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
