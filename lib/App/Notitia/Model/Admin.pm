package App::Notitia::Model::Admin;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SLOT_TYPE_ENUM TRUE TYPE_CLASS_ENUM );
use App::Notitia::Form      qw( blank_form f_list f_tag p_button p_container
                                p_select p_rows p_table p_textfield );
use App::Notitia::Util      qw( bind bind_fields button create_link loc locm
                                make_tip management_link operation_links
                                register_action_paths to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_arrayref is_member throw );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'admin';

register_action_paths
   'admin/slot_certs' => 'slot-certs',
   'admin/slot_roles' => 'slot-roles',
   'admin/type'       => 'type',
   'admin/types'      => 'types';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav }->{list    }   = $self->admin_navigation_links( $req );
   $stash->{page}->{location} //= 'admin';

   return $stash;
};

# Private functions
my $_add_type_create_links = sub {
   my ($req, $moniker, $type_class) = @_;

   my $actionp = "${moniker}/type"; my $links = [];

   if ($type_class) {
      my $k = "${type_class}_type"; my $opts = { args => [ $type_class ] };

      push @{ $links }, create_link( $req, $actionp, $k, $opts );
   }
   else {
      for my $type_class (@{ TYPE_CLASS_ENUM() }) {
         my $k = "${type_class}_type"; my $opts = { args => [ $type_class ] };

         push @{ $links }, create_link( $req, $actionp, $k, $opts );
      }
   }

   return f_list '&nbsp;|&nbsp;', $links;
};

my $_list_slot_certs = sub {
   my ($schema, $slot_type) = @_; my $rs = $schema->resultset( 'SlotCriteria' );

   return  [ map { $_->certification_type }
             $rs->search( { 'slot_type' => $slot_type },
                          { prefetch    => 'certification_type' } )->all ];
};

my $_maybe_find_type = sub {
   return $_[ 2 ] ? $_[ 0 ]->find_type_by( $_[ 2 ], $_[ 1 ] )
                  : Class::Null->new;
};

my $_slot_roles_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "slot_roles_heading_${_}" ) } }
            0 .. 1 ];
};

my $_slot_roles_links = sub {
   my ($req, $moniker, $slot_role) = @_;

   my $actionp = $moniker.'/slot_certs'; my $opts = { args => [ $slot_role ] };

   my @links = { value => management_link( $req, $actionp, $slot_role, $opts )};

   return [ { value => loc( $req, $slot_role ) }, @links ];
};

my $_subtract = sub {
   return [ grep { is_arrayref $_ or not is_member $_, $_[ 1 ] } @{ $_[ 0 ] } ];
};

my $_types_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "types_heading_${_}" ) } } 0 .. 2 ];
};

my $_types_links = sub {
   my ($req, $type) = @_; my $name = $type->name;

   my $opts = { args => [ $type->type_class, $name ] };

   return [ { value => ucfirst $type->type_class },
            { value => loc( $req, $type->name ) },
            { value => management_link( $req, 'admin/type', $name, $opts ) } ];
};

# Private methods
my $_list_all_certs = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ $type_rs->search_for_certification_types->all ];
};

# Public methods
sub add_certification_action : Role(administrator) {
   my ($self, $req) = @_;

   my $slot_type = $req->uri_params->( 0 );
   my $type_rs   = $self->schema->resultset( 'Type' );
   my $certs     = $req->body_params->( 'certs', { multiple => TRUE } );

   for my $cert_name (@{ $certs }) {
      my $cert_type = $type_rs->find_certification_by( $cert_name );

      $cert_type->add_cert_type_to( $slot_type );
   }

   my $message  = [ to_msg '[_1] slot role cert(s). added by [_2]',
                    $slot_type, $req->session->user_label ];
   my $location = uri_for_action $req, $self->moniker.'/slot_roles';

   return { redirect => { location => $location, message => $message } };
}

sub add_type_action : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $name     =  $req->body_params->( 'name' );
   my $person   =  $self->schema->resultset( 'Type' )->create( {
      name      => $name, type_class => $type_class } );
   my $message  =  [ to_msg 'Type [_1] class [_2] created by [_3]',
                     $name, $type_class, $req->session->user_label ];
   my $location =  uri_for_action $req, $self->moniker.'/types';

   return { redirect => { location => $location, message => $message } };
}

sub remove_certification_action : Role(administrator) {
   my ($self, $req) = @_;

   my $slot_type = $req->uri_params->( 0 );
   my $type_rs   = $self->schema->resultset( 'Type' );
   my $certs     = $req->body_params->( 'slot_certs', { multiple => TRUE } );

   for my $cert_name (@{ $certs }) {
      my $cert_type = $type_rs->find_certification_by( $cert_name );

      $cert_type->delete_cert_type_from( $slot_type );
   }

   my $message  = [ to_msg '[_1] slot role cert(s). deleted by [_2]',
                    $slot_type, $req->session->user_label ];
   my $location = uri_for_action $req, $self->moniker.'/slot_roles';

   return { redirect => { location => $location, message => $message } };
}

sub remove_type_action : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $name     = $req->uri_params->( 1 );
   my $type_rs  = $self->schema->resultset( 'Type' );
   my $type     = $type_rs->find_type_by( $name, $type_class ); $type->delete;
   my $message  = [ to_msg 'Type [_1] class [_2] deleted by [_3]',
                    $name, $type_class, $req->session->user_label ];
   my $location =  uri_for_action $req, $self->moniker.'/types';

   return { redirect => { location => $location, message => $message } };
}

sub slot_certs : Role(administrator) {
   my ($self, $req) = @_;

   my $slot_type  =  $req->uri_params->( 0 );
   my $actionp    =  $self->moniker.'/slot_certs';
   my $href       =  uri_for_action $req, $actionp, [ $slot_type ];
   my $form       =  blank_form 'role-certs-admin', $href;
   my $page       =  {
      forms       => [ $form ],
      title       => loc( $req, 'slot_certs_management_heading' ), };
   my $slot_certs =  $_list_slot_certs->( $self->schema, $slot_type );
   my $available  =  $_subtract->( $self->$_list_all_certs, $slot_certs );

   p_textfield $form, 'slotname', loc( $req, $slot_type ), { disabled => TRUE };

   p_select $form, 'slot_certs', $slot_certs, { multiple => TRUE, size => 5 };

   p_button $form, 'remove_certification', 'remove_certification', {
      class => 'delete-button', container_class => 'right-last',
      tip   => make_tip( $req, 'remove_certification_tip',
                         [ 'certification', $slot_type ] ) };

   p_container $form, f_tag( 'hr' ), { class => 'form-separator' };

   p_select $form, 'certs', $available, { multiple => TRUE, size => 10 };

   p_button $form, 'add_certification', 'add_certification', {
      class => 'save-button', container_class => 'right-last',
      tip   => make_tip( $req, 'add_certification_tip',
                         [ 'certification', $slot_type ] ) };

   return $self->get_stash( $req, $page );
};

sub slot_roles : Role(administrator) {
   my ($self, $req) = @_;

   my $form    =  blank_form;
   my $page    =  {
      forms    => [ $form ],
      title    => loc $req, 'slot_roles_list_link' };
   my $table   =  p_table $form, { headers => $_slot_roles_headers->( $req ) };

   p_rows $table, [ map { $_slot_roles_links->( $req, $self->moniker, $_ ) }
                       @{ SLOT_TYPE_ENUM() } ];

   return $self->get_stash( $req, $page );
}

sub type : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $actionp    =  $self->moniker.'/type';
   my $name       =  $req->uri_params->( 1, { optional => TRUE } );
   my $type_rs    =  $self->schema->resultset( 'Type' );
   my $type       =  $_maybe_find_type->( $type_rs, $type_class, $name );
   my $args       =  [ $type_class ]; $name and push @{ $args }, $name;
   my $href       =  uri_for_action $req, $actionp, $args;
   my $form       =  blank_form 'type-admin', $href;
   my $disabled   =  $name ? TRUE : FALSE;
   my $class_name =  ucfirst $type_class;
   my $page       =  {
      first_field => 'name',
      forms       => [ $form ],
      title       => locm $req, 'type_management_heading', $class_name };

   p_textfield $form, 'name', loc( $req, $type->name ), {
      disabled => $disabled, label => 'type_name' };

   if ($name) {
      p_button $form, 'remove_type', 'remove_type', {
         class => 'delete-button', container_class => 'right-last',
         tip   => make_tip( $req, 'remove_type_tip', $args ) };
   }
   else {
      p_button $form, 'add_type', 'add_type', {
         class => 'save-button', container_class => 'right-last',
         tip   => make_tip( $req, 'add_type_tip', $args ) };
   }

   return $self->get_stash( $req, $page );
}

sub types : Role(administrator) {
   my ($self, $req) = @_;

   my $moniker    =  $self->moniker;
   my $type_class =  $req->query_params->( 'type_class', { optional => TRUE } );
   my $form       =  blank_form;
   my $page       =  {
      forms       => [ $form ],
      title       => loc( $req, $type_class ? "${type_class}_list_link"
                                            : 'types_management_heading' ), };
   my $type_rs    =  $self->schema->resultset( 'Type' );
   my $types      =  $type_class ? $type_rs->search_for_types( $type_class )
                                 : $type_rs->search_for_all_types;
   my $links      =  $_add_type_create_links->( $req, $moniker, $type_class );

   p_container $form, $links, {
      class => 'operation-links align-right right-last' };

   my $table = p_table $form, { headers => $_types_headers->( $req ) };

   p_rows $table, [ map { $_types_links->( $req, $_ ) } $types->all ];

   p_container $form, $links, {
      class => 'operation-links align-right right-last' };

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Admin - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Admin;
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
