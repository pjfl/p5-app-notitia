package App::Notitia::Model::Role;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::DOM       qw( new_container f_tag p_button p_container
                                p_select p_textfield );
use App::Notitia::Util      qw( loc make_tip register_action_paths to_msg );
use Class::Usul::Functions  qw( is_arrayref is_member throw );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

# Public attributes
has '+moniker' => default => 'role';

register_action_paths 'role/role' => 'role';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'management';
   $stash->{navigation}
      = $self->management_navigation_links( $req, $stash->{page} );
   return $stash;
};

# Private functions
my $_subtract = sub {
   return [ grep { is_arrayref $_ or not is_member $_, $_[ 1 ] } @{ $_[ 0 ] } ];
};

# Private methods
my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ $type_rs->search_for_role_types->all ];
};

# Public methods
sub add_role_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->schema->resultset( 'Person' )->find_by_shortcode( $name);
   my $roles  = $req->body_params->( 'roles', { multiple => TRUE } );

   for my $role (@{ $roles }) {
      $person->add_member_to( $role );

      my $message = "action:add-role shortcode:${name} role:${role}";

      $self->send_event( $req, $message );
   }

   $self->state_cache( 'roles_mtime', time );

   my $location = $req->uri_for_action( $self->moniker.'/role', [ $name ] );
   my $message  = [ to_msg '[_1] role(s) added by [_2]',
                    $person->label, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub remove_role_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->schema->resultset( 'Person' )->find_by_shortcode( $name);
   my $roles  = $req->body_params->( 'person_roles', { multiple => TRUE } );

   for my $role (@{ $roles }) {
      $role eq 'administrator' and $name eq 'admin' and next;
      $person->delete_member_from( $role );

      my $message = "action:delete-role shortcode:${name} role:${role}";

      $self->send_event( $req, $message );
   }

   $self->state_cache( 'roles_mtime', time );

   my $location = $req->uri_for_action( $self->moniker.'/role', [ $name ] );
   my $message  = [ to_msg '[_1] role(s) removed by [_2]',
                    $person->label, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub role : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name      =  $req->uri_params->( 0 );
   my $role      =  $req->query_params->( 'role', { optional => TRUE } );
   my $status    =  $req->query_params->( 'status', { optional => TRUE } );
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $person    =  $person_rs->find_by_shortcode( $name );
   my $href      =  $req->uri_for_action( $self->moniker.'/role', [ $name ] );
   my $form      =  new_container 'role-admin', $href;
   my $page      =  {
      forms      => [ $form ],
      selected   => $role ? "${role}_list"
                  : $status && $status eq 'current' ? 'current_people_list'
                  : 'people_list',
      title      => loc $req, 'role_management_heading' };

   my $person_roles = $person->list_roles;
   my $available    = $_subtract->( $self->$_list_all_roles, $person_roles );

   p_textfield $form, 'username', $person->label, { disabled => TRUE };

   p_select $form, 'person_roles', $person_roles, {
      multiple => TRUE, size => 5 };

   p_button $form, 'remove_role', 'remove_role', {
      class => 'delete-button', container_class => 'right-last',
      tip   => make_tip( $req, 'remove_role_tip', [ 'role', $name ] ) };

   p_container $form, f_tag( 'hr' ), { class => 'form-separator' };

   p_select $form, 'roles', $available, { multiple => TRUE, size => 5 };

   p_button $form, 'add_role', 'add_role', {
      class => 'save-button', container_class => 'right-last',
      tip   => make_tip( $req, 'add_role_tip', [ 'role', $name ] ) };

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
