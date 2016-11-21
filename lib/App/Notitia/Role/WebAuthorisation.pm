package App::Notitia::Role::WebAuthorisation;

use attributes ();
use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS );
use Class::Usul::Functions  qw( is_member throw );
use Scalar::Util            qw( blessed );
use Unexpected::Functions   qw( AuthenticationRequired );
use Moo::Role;

requires qw( components config execute );

# Private functions
my $_list_roles = sub {
   my ($self, $req) = @_; my $roles_mtime = $self->config->roles_mtime;

   my $session = $req->session; my $roles = $session->roles; my $person;

   $roles_mtime = $roles_mtime->exists ? $roles_mtime->stat->{mtime} : 0;

   $session->roles_mtime < $roles_mtime and $roles = [];

   unless (defined $roles->[ 0 ]) {
      $person = $self->components->{person}->find_by_shortcode( $req->username);
      $person and $session->roles( $roles = $person->list_roles );
      defined $roles->[ 0 ] and $session->roles_mtime( $roles_mtime );
   }

   return $roles, $person ? $person->label : $req->username;
};

my $_list_roles_of = sub {
   my $attr = attributes::get( shift ) // {}; return $attr->{Role} // [];
};

# Construction
around 'execute' => sub {
   my ($orig, $self, $method, $req) = @_; my $class = blessed $self || $self;

   my $code_ref = $self->can( $method )
      or throw 'Class [_1] has no method [_2]', [ $class, $method ];

   my $method_roles = $_list_roles_of->( $code_ref ); $method_roles->[ 0 ]
      or throw 'Class [_1] method [_2] is private', [ $class, $method ];

   is_member 'anon', $method_roles and return $orig->( $self, $method, $req );

   $req->authenticated or throw AuthenticationRequired, [ $req->path ];

   is_member 'any',  $method_roles and return $orig->( $self, $method, $req );

   my ($roles, $name) = $self->$_list_roles( $req );

   for my $role_name (@{ $roles }) {
      is_member $role_name, $method_roles
         and return $orig->( $self, $method, $req );
   }

   throw '[_1] permission to [_2] denied',
      [ $req->session->user_label || $name, $self->moniker."/${method}" ];
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
