package App::Notitia::Model;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Types      qw( Plinth );
use HTTP::Status            qw( HTTP_BAD_REQUEST HTTP_OK );
use Scalar::Util            qw( blessed );
use Unexpected::Functions   qw( ValidationErrors );
use Moo;

with q(Web::Components::Role);

# Public attributes
has 'application' => is => 'ro', isa => Plinth,
   required       => TRUE,  weak_ref => TRUE;

# Public methods
sub exception_handler {
   my ($self, $req, $e) = @_;

   my $page  = { error    => $e,
                 template => [ 'nav_panel', 'exception' ],
                 title    => $req->loc( 'Exception Handler' ) };

   $e->class eq ValidationErrors->() and $page->{validation_error} = $e->args;

   my $stash = $self->get_stash( $req, $page );

   $stash->{code} = $e->rv >= HTTP_OK ? $e->rv : HTTP_BAD_REQUEST;

   return $stash;
}

sub execute {
   my ($self, $method, @args) = @_;

   $self->can( $method ) and return $self->$method( @args );

   throw 'Class [_1] has no method [_2]', [ blessed $self, $method ];
}

sub get_stash {
   my ($self, $req, $page) = @_;

   my $stash = $self->initialise_stash( $req );

   $stash->{page} = $self->load_page( $req, $page );

   return $stash;
}

sub initialise_stash {
   return { code => HTTP_OK, view => $_[ 0 ]->config->default_view, };
}

sub load_page {
   my ($self, $req, $page) = @_; $page //= {}; return $page;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model;
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
