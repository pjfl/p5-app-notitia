package App::Notitia::Markdown;

use strictures;
use parent 'Text::MultiMarkdown';

sub _DoCodeBlocks { # Add support for triple graves
   my ($self, $text) = @_;

   $text =~ s{
      (?:(?:\n```(.*)\n)|\n\n|\A)
         (
           (?:
            (?:[ ]{$self->{tab_width}} | \t)
            .*\n+
            )+
           )
         (?:^```(.*)?|(?=^[ ]{0,$self->{tab_width}}\S)|\Z)
      }{
         my $class = $1 || $3 || q(); my $codeblock = $2; my $result;

         $codeblock = $self->_EncodeCode( $self->_Outdent( $codeblock ) );
         $codeblock = $self->_Detab( $codeblock );
         $codeblock =~ s/\A\n+//;
         $codeblock =~ s/\n+\z//;
         $class and $class = " class=\"${class}\"";
         $result = "\n\n<pre><code${class}>${codeblock}\n</code></pre>\n\n";
         $result;
      }egmx;

   return $text;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Markdown - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Markdown;
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
