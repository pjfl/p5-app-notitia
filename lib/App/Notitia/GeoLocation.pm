package App::Notitia::GeoLocation;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS );
use Class::Usul::Functions  qw( ensure_class_loaded first_char );
use Class::Usul::Types      qw( ClassName HashRef );
use Moo;

has 'provider' => is => 'lazy', isa => sub { __PACKAGE__.'::Base' },
   builder => sub { $_[ 0 ]->provider_class->new( $_[ 0 ]->provider_attr ) },
   handles => [ 'locate_by_postcode' ];

has 'provider_attr' => is => 'ro', isa => HashRef;

has 'provider_class' => is => 'ro', isa => ClassName;

around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $class = delete $attr->{provider};

   if (first_char $class eq '+') { $class = substr $class, 1 }
   else { $class = __PACKAGE__."::${class}" }

   ensure_class_loaded $class;

   return { provider_attr => $attr, provider_class => $class };
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
