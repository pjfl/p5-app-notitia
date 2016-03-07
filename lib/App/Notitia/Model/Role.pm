package App::Notitia::Model::Role;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TILDE TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind loc
                                register_action_paths uri_for_action );
use Class::Usul::Functions  qw( is_arrayref is_member throw );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'role';

register_action_paths 'role/role' => 'role';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Private functions
my $_add_role_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'add_role_tip', [ 'role', $name ] );

   return { container_class => 'right', label => 'add_role',
            tip             => $tip,    value => 'add_role' };
};

my $_remove_role_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'remove_role_tip', [ 'role', $name ] );

   return { container_class => 'right', label => 'remove_role',
            tip             => $tip,    value => 'remove_role' };
};

my $_subtract = sub {
   return [ grep { is_arrayref $_ or not is_member $_, $_[ 1 ] } @{ $_[ 0 ] } ];
};

# Private methods
my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->list_role_types->all ];
};

# Public methods
sub add_role_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->schema->resultset( 'Person' )->find_person_by( $name );
   my $roles  = $req->body_params->( 'roles', { multiple => TRUE } );

   $person->add_member_to( $_ ) for (@{ $roles });

   my $location = uri_for_action( $req, $self->moniker.'/role', [ $name ] );
   my $message  =
      [ 'Person [_1] role(s) added by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub remove_role_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->schema->resultset( 'Person' )->find_person_by( $name );
   my $roles  = $req->body_params->( 'person_roles', { multiple => TRUE } );

   $person->delete_member_from( $_ ) for (@{ $roles });

   my $location = uri_for_action( $req, $self->moniker.'/role', [ $name ] );
   my $message  =
      [ 'Person [_1] role(s) removed by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub role : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name      =  $req->uri_params->( 0 );
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $person    =  $person_rs->find_person_by( $name );
   my $href      =  uri_for_action( $req, $self->moniker.'/role', [ $name ] );
   my $page      =  {
      fields     => { username => { href => $href } },
      template   => [ 'contents', 'role' ],
      title      => loc( $req, 'role_management_heading' ), };
   my $fields    =  $page->{fields};

   my $person_roles = $person->list_roles;
   my $available    = $_subtract->( $self->$_list_all_roles, $person_roles );

   $fields->{roles}
      = bind( 'roles', $available, { multiple => TRUE, size => 10 } );
   $fields->{person_roles}
      = bind( 'person_roles', $person_roles, { multiple => TRUE, size => 10 } );
   $fields->{add   } = $_add_role_button->( $req, $name );
   $fields->{remove} = $_remove_role_button->( $req, $name );

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Role - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Role;
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
