package App::Notitia::Role::WebAuthorisation;

use attributes ();
use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS );
use Class::Usul::Functions  qw( is_member throw );
use HTTP::Status            qw( HTTP_FORBIDDEN HTTP_NOT_FOUND
                                HTTP_UNAUTHORIZED );
use Scalar::Util            qw( blessed );
use Unexpected::Functions   qw( AuthenticationRequired );
use Moo::Role;

requires qw( components config execute );

# Private functions
my $_list_roles_of = sub {
   my $attr = attributes::get( shift ) // {}; return $attr->{Role} // [];
};

# Construction
around 'execute' => sub {
   my ($orig, $self, $method, $req) = @_; my $class = blessed $self || $self;

   my $code_ref = $self->can( $method )
      or throw 'Class [_1] has no method [_2]', [ $class, $method ],
               rv => HTTP_NOT_FOUND;

   my $method_roles = $_list_roles_of->( $code_ref ); $method_roles->[ 0 ]
      or throw 'Class [_1] method [_2] is private', [ $class, $method ],
               rv => HTTP_FORBIDDEN;

   is_member 'anon', $method_roles and return $orig->( $self, $method, $req );

   $req->authenticated or throw AuthenticationRequired,
                                [ $req->path ], rv => HTTP_UNAUTHORIZED;

   is_member 'any', $method_roles and return $orig->( $self, $method, $req );

   my $person = $self->components->{admin}->find_person_by( $req->username );

   for my $role_name (@{ $person->list_roles }) {
      is_member $role_name, $method_roles
         and return $orig->( $self, $method, $req );
   }

   throw 'Person [_1] permission denied', [ $req->username ],
         rv => HTTP_FORBIDDEN;
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::WebAuthorisation - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::WebAuthorisation;
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
