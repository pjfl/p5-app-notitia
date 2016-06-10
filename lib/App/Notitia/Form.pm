package App::Notitia::Form;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Constants qw( FALSE NUL );
use Class::Usul::Functions  qw( is_arrayref );
use Scalar::Util            qw( blessed );

our @EXPORT_OK = qw( blank_form f_image p_button p_checkbox p_label
                     p_password p_radio p_text p_textfield );

# Private functions functions
my $_bind_option = sub {
   my ($v, $opts) = @_;

   my $prefix = $opts->{prefix} // NUL; my $numify = $opts->{numify} // FALSE;

   return is_arrayref $v
        ? { label =>  $v->[ 0 ].NUL,
            value => (defined $v->[ 1 ] ? ($numify ? 0 + ($v->[ 1 ] || 0)
                                                   : $prefix.$v->[ 1 ])
                                        : undef),
            %{ $v->[ 2 ] // {} } }
        : { label => "${v}", value => ($numify ? 0 + $v : $prefix.$v) };
};

my $_bind = sub {
   my ($name, $v, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{name} = $name; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $opts->{value} = $v->set_time_zone( 'local' )->dmy( '/' );
   }
   elsif (is_arrayref $v) {
      $opts->{value} = [ map { $_bind_option->( $_, $opts ) } @{ $v } ];
   }
   elsif (defined $v) { $opts->{value} = $opts->{numify} ? 0 + $v : "${v}" }
   else { $opts->{value} = NUL }

   return $opts;
};

my $_push_field = sub {
   my ($form, $type, $opts) = @_; $opts = { %{ $opts } };

   $opts->{type} = $type; $opts->{label} //= $opts->{name};

   return push @{ $form->{content}->{list} }, $opts;
};

# Public functions
sub blank_form ($$) {
   my ($name, $href) = @_;

   return { content   => { list => [], type => 'list' }, href => $href,
            form_name => $name, type => 'form' },
}

sub f_image {
   return { href => $_[ 1 ], title => $_[ 0 ], type => 'image' };
}

sub p_button ($@) {
   my $f = shift; return $_push_field->( $f, 'button', $_bind->( @_ ) );
}

sub p_checkbox ($@) {
   my $f = shift; return $_push_field->( $f, 'checkbox', $_bind->( @_ ) );
}

sub p_label ($@) {
   my ($f, $label, $content, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{content} = $content; $opts->{label} = $label;

   return $_push_field->( $f, 'label', $opts );
}

sub p_password ($@) {
   my $f = shift; return $_push_field->( $f, 'password', $_bind->( @_ ) );
}

sub p_radio ($@) {
   my $f = shift; return $_push_field->( $f, 'radio', $_bind->( @_ ) );
}

sub p_text ($@) {
   my $f = shift; return $_push_field->( $f, 'text', $_bind->( @_ ) );
}

sub p_textfield ($@) {
   my $f = shift; return $_push_field->( $f, 'textfield', $_bind->( @_ ) );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Form - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Form;
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
