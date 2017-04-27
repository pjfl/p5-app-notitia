package App::Notitia::Model::UserForm;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FIELD_TYPE_ENUM FALSE HASH_CHAR
                                NUL PIPE_SEP TRUE );
use App::Notitia::DOM       qw( new_container p_action p_checkbox p_item p_js
                                p_link p_list p_row p_select p_table p_tag
                                p_textfield );
use App::Notitia::Util      qw( dialog_anchor link_options locm
                                register_action_paths
                                set_element_focus to_msg );
use Class::Null;
use Class::Usul::Functions  qw( throw );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

# Public attributes
has '+moniker' => default => 'form';

register_action_paths
   'form/field_view' => 'form/*/field',
   'form/form_list'  => 'forms',
   'form/form_view'  => 'form';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_field_headers = sub {
   return [ map { { value => locm $_[ 0 ], "user_field_heading_${_}" } }
            0 .. 2 ];
};

my $_field_type = sub {
   return [ ucfirst $_[ 1 ], $_[ 1 ], {
      selected => $_ eq $_[ 0 ]->field_type ? TRUE : FALSE } ];
};

my $_field_types = sub {
   my $field = shift;

   return [ [ NUL, undef ],
            map { $_field_type->( $field, $_ ) } @{ FIELD_TYPE_ENUM() } ];
};

my $_forms_headers = sub {
   return [ map { { value => locm $_[ 0 ], "user_form_list_heading_${_}" } }
            0 .. 0 ];
};

# Private methods
my $_field_dialog_link = sub {
   my ($self, $req, $page, $form, $field, $cells) = @_;

   my $name = 'field_'.$field->name.'_edit';

   p_item $cells, p_link {}, $name, HASH_CHAR, {
      class   => 'windows',
      request => $req,
      tip     => locm( $req, 'user_field_edit_tip' ),
      value   => $field->name };

   my $args = [ $form->name, $field->name ];
   my $href = $req->uri_for_action( $self->moniker.'/field_view', $args );

   p_js $page, dialog_anchor $name, $href, {
      title => locm $req, 'user_field_dialog_title' };

   return;
};

my $_field_cells = sub {
   my ($self, $req, $page, $form, $field) = @_; my $cells = [];

   if ($field->name eq 'id') { p_item $cells, "${field}" }
   else { $self->$_field_dialog_link( $req, $page, $form, $field, $cells ) }

   p_item $cells, $field->field_type;

   p_item $cells, $field->label;

   return $cells;
};

my $_field_ops_links = sub {
   my ($self, $req, $page, $form) = @_; my $links = [];

   p_link $links, my $name = 'user_field', HASH_CHAR, {
      action  => 'create', class => 'windows', container_class => 'add-link',
      request => $req };

   my $args = [ $form->name ];
   my $href = $req->uri_for_action( $self->moniker.'/field_view', $args );

   p_js $page, dialog_anchor "create_${name}", $href, {
      name => $name, title => locm $req, "${name}_dialog_title" };

   return $links;
};

my $_field_list = sub {
   my ($self, $req, $page, $form) = @_;

   my $form_1 = $page->{forms}->[ 1 ] = new_container { class => 'wide-form' };
   my $links  = $self->$_field_ops_links( $req, $page, $form );

   p_tag  $form_1, 'h5', locm $req, 'user_field_title';
   p_list $form_1, PIPE_SEP, $links, link_options 'right';

   my $fields   = p_table $form_1, { headers => $_field_headers->( $req ) };
   my $field_rs = $self->schema->resultset( 'UserField' );

   p_row $fields, [ map { $self->$_field_cells( $req, $page, $form, $_ ) }
                    $field_rs->search( { form_id => $form->id } )->all ];

   p_list $form_1, PIPE_SEP, $links, link_options 'right';
   return;
};

my $_find_user_form = sub {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0 );
   my $rs   = $self->schema->resultset( 'UserForm' );
   my $form = $rs->search( { name => $name } )->first
      or throw 'User form [_1] unknown', args => [ $name ], level => 2;

   return $form;
};

my $_forms_ops_links = sub {
   my ($self, $req) = @_; my $links = [];

   my $href = $req->uri_for_action( $self->moniker.'/form_view' );

   p_link $links, 'user_form', $href, {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_forms_cells = sub {
   my ($self, $req, $form) = @_; my $cells = [];

   my $args = [ $form->name ];
   my $href = $req->uri_for_action( $self->moniker.'/form_view', $args );

   p_item $cells, p_link {}, 'user_form_update', $href, {
      request => $req, value => $form->name };

   return $cells;
};

my $_maybe_find_field = sub {
   my ($self, $form, $name) = @_; $name or return Class::Null->new;

   my $args  = [ "${form}", $name ];
   my $field = $self->schema->resultset( 'UserField' )->find( $form->id, $name )
      or throw 'User field [_1].[_2] unknown', args => $args, level => 2;

   return $field;
};

my $_maybe_find_form = sub {
   my ($self, $name) = @_; $name or return Class::Null->new;

   my $rs   = $self->schema->resultset( 'UserForm' );
   my $form = $rs->search( { name => $name } )->first
      or throw 'User form [_1] unknown', args => [ $name ], level => 2;

   return $form;
};

# Public methods
sub create_user_field_action : Role(administrator) {
   my ($self, $req) = @_;

   my $form     = $self->$_find_user_form( $req );
   my $params   = $req->body_params;
   my $field    = $self->schema->resultset( 'UserField' )->create( {
      form_id    => $form->id,
      name       => $params->( 'name' ),
      field_type => $params->( 'field_type' ),
   } );
   my $args     = [ $form->name ];
   my $message  = [ to_msg 'User field [_1] created by [_2]',
                    $field, $req->session->user_label ];
   my $location = $req->uri_for_action( $self->moniker.'/form_view', $args );

   return { redirect => { location => $location, message => $message } };
}

sub create_user_form_action : Role(administrator) {
   my ($self, $req) = @_;

   my $params   = $req->body_params;
   my $rs       = $self->schema->resultset( 'UserForm' );
   my $form     = $rs->create( { name => $params->( 'name' ) } );
   my $message  = [ to_msg 'User form [_1] created by [_2]',
                    $form, $req->session->user_label ];
   my $location = $req->uri_for_action( $self->moniker.'/form_list' );

   return { redirect => { location => $location, message => $message } };
}

sub delete_user_field_action : Role(administrator) {
   my ($self, $req) = @_;

   my $form  = $self->$_find_user_form( $req );
   my $name  = $req->uri_params->( 1 );
   my $rs    = $self->schema->resultset( 'UserField' );
   my $field = $rs->find( $form->id, $name )
      or throw 'User field [_1].[_2] unknown', [ "${form}", $name ];

   $field->delete;

   my $args     = [ $form->name ];
   my $location = $req->uri_for_action( $self->moniker.'/form_view', $args );
   my $message  = [ to_msg 'User field [_1] deleted by [_2]',
                    $field, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_user_form_action : Role(administrator) {
   my ($self, $req) = @_;

   my $form = $self->$_find_user_form( $req );

   $form->delete;

   my $message  = [ to_msg 'User form [_1] deleted by [_2]',
                    $form, $req->session->user_label ];
   my $location = $req->uri_for_action( $self->moniker.'/form_list' );

   return { redirect => { location => $location, message => $message } };
}

sub field_view : Dialog Role(administrator) {
   my ($self, $req) = @_;

   my $form_name  = $req->uri_params->( 0 );
   my $field_name = $req->uri_params->( 1, { optional => TRUE } );
   my $stash  = $self->dialog_stash( $req );
   my $args   = [ $form_name, $field_name ];
   my $href   = $req->uri_for_action( $self->moniker.'/field_view', $args );
   my $form_0 = $stash->{page}->{forms}->[ 0 ] = new_container 'field', $href;
   my $form   = $self->$_find_user_form( $req );
   my $field  = $self->$_maybe_find_field( $form, $field_name );

   p_js $stash->{page}, set_element_focus 'field', 'name';

   p_textfield $form_0, 'name', $field->name, {
      class => 'standard-field required', label => 'user_field_name' };

   p_select $form_0, 'field_type', $_field_types->( $field ), {
      class => 'single-character required', };

   if ($field->name) {
      my $args = [ 'user_field', $field_name ];

      p_action $form_0, 'update', $args, { request => $req };
      p_action $form_0, 'delete', $args, { request => $req };
   }
   else { p_action $form_0, 'create', [ 'user_field' ], { request => $req } }

   return $stash;
}

sub form_list : Role(administrator) {
   my ($self, $req) = @_;

   my $page    = {
      selected => 'user_form_list',
      title    => locm $req, 'user_form_list_title',
   };
   my $form_0 = $page->{forms}->[ 0 ] = new_container;
   my $links  = $self->$_forms_ops_links( $req );

   p_list $form_0, PIPE_SEP, $links, link_options 'right';

   my $table   = p_table $form_0, { headers => $_forms_headers->( $req ) };
   my $form_rs = $self->schema->resultset( 'UserForm' );

   p_row $table, [ map { $self->$_forms_cells( $req, $_ ) } $form_rs->all ];

   p_list $form_0, PIPE_SEP, $links, link_options 'right';

   return $self->get_stash( $req, $page );
}

sub form_view : Role(administrator) {
   my ($self, $req) = @_;

   my $page   = {
      first_field => 'name',
      selected    => 'user_form_list',
      title       => locm $req, 'user_form_title', };
   my $name   = $req->uri_params->( 0, { optional => TRUE } );
   my $href   = $req->uri_for_action( $self->moniker.'/form_view', [ $name ] );
   my $form_0 = $page->{forms}->[ 0 ] = new_container 'user-form', $href;
   my $form   = $self->$_maybe_find_form( $name );

   p_textfield $form_0, 'name', $form->name, {
      disabled => $name ? TRUE : FALSE, label => 'user_form_name' };

   if ($form->name) {
      p_action $form_0, 'delete', [ 'user_form', $name ], { request => $req };
      $self->$_field_list( $req, $page, $form );
   }
   else { p_action $form_0, 'create', [ 'user_form' ], { request => $req } }

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::UserForm - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::UserForm;
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
