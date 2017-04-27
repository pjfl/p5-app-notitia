package App::Notitia::Model::UserTable;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( DATA_TYPE_ENUM FALSE HASH_CHAR
                                NUL PIPE_SEP TRUE );
use App::Notitia::DOM       qw( new_container p_action p_checkbox  p_item p_js
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
has '+moniker' => default => 'table';

register_action_paths
   'table/column_view' => 'table/*/column',
   'table/table_list'  => 'tables',
   'table/table_view'  => 'table';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_column_headers = sub {
   return [ map { { value => locm $_[ 0 ], "user_column_heading_${_}" } }
            0 .. 2 ];
};

my $_data_type = sub {
   return [ $_[ 1 ], $_[ 1 ], {
      selected => $_ eq $_[ 0 ]->data_type ? TRUE : FALSE } ];
};

my $_data_types = sub {
   my $column = shift;

   return [ [ NUL, undef ],
            map { $_data_type->( $column, $_ ) } @{ DATA_TYPE_ENUM() } ];
};

my $_table_page = sub {
   my ($req, @forms) = @_;

   return {
      first_field => 'name',
      forms       => [ @forms ],
      selected    => 'user_table_list',
      title       => locm $req, 'user_table_title'
   };
};

my $_tables_headers = sub {
   return [ map { { value => locm $_[ 0 ], "user_table_list_heading_${_}" } }
            0 .. 0 ];
};

# Private methods
my $_column_dialog_link = sub {
   my ($self, $req, $page, $table, $column, $cells) = @_;

   my $name = 'column_'.$column->name.'_edit';

   p_item $cells, p_link {}, $name, HASH_CHAR, {
      class   => 'windows',
      request => $req,
      tip     => locm( $req, 'user_column_edit_tip' ),
      value   => $column->name };

   my $args = [ $table->name, $column->name ];
   my $href = $req->uri_for_action( $self->moniker.'/column_view', $args );

   p_js $page, dialog_anchor $name, $href, {
      title => locm $req, 'user_column_dialog_title' };

   return;
};

my $_column_cells = sub {
   my ($self, $req, $page, $table, $column) = @_; my $cells = [];

   if ($column->name eq 'id') { p_item $cells, "${column}" }
   else { $self->$_column_dialog_link( $req, $page, $table, $column, $cells ) }

   p_item $cells, $column->data_type;

   p_item $cells, $column->default_value;

   return $cells;
};

my $_column_ops_links = sub {
   my ($self, $req, $page, $table) = @_; my $links = [];

   p_link $links, my $name = 'user_column', HASH_CHAR, {
      action  => 'create', class => 'windows', container_class => 'add-link',
      request => $req };

   my $args = [ $table->name ];
   my $href = $req->uri_for_action( $self->moniker.'/column_view', $args );

   p_js $page, dialog_anchor "create_${name}", $href, {
      name => $name, title => locm $req, "${name}_dialog_title" };

   return $links;
};

my $_find_user_table = sub {
   my ($self, $req) = @_;

   my $name  = $req->uri_params->( 0 );
   my $rs    = $self->schema->resultset( 'UserTable' );
   my $table = $rs->search( { name => $name } )->first
      or throw 'User table [_1] unknown', args => [ $name ], level => 2;

   return $table;
};

my $_maybe_find_column = sub {
   my ($self, $table, $name) = @_; $name or return Class::Null->new;

   my $rs     = $self->schema->resultset( 'UserColumn' );
   my $column = $rs->find( $table->id, $name )
      or throw 'User column [_1].[_2] unknown', [ $table->name, $name ];

   return $column;
};

my $_maybe_find_table = sub {
   my ($self, $name) = @_; $name or return Class::Null->new;

   my $rs    = $self->schema->resultset( 'UserTable' );
   my $table = $rs->search( { name => $name } )->first
      or throw 'User table [_1] unknown', args => [ $name ], level => 2;

   return $table;
};

my $_tables_cells = sub {
   my ($self, $req, $table) = @_; my $cells = [];

   my $args = [ $table->name ];
   my $href = $req->uri_for_action( $self->moniker.'/table_view', $args );

   p_item $cells, p_link {}, 'user_table_update', $href, {
      request => $req, value => $table->name };

   return $cells;
};

my $_tables_ops_links = sub {
   my ($self, $req) = @_; my $links = [];

   my $href = $req->uri_for_action( $self->moniker.'/table_view' );

   p_link $links, 'user_table', $href, {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

# Public methods
sub column_view : Dialog Role(administrator) {
   my ($self, $req) = @_;

   my $table_name  = $req->uri_params->( 0 );
   my $column_name = $req->uri_params->( 1, { optional => TRUE } );
   my $stash  = $self->dialog_stash( $req );
   my $args   = [ $table_name, $column_name ];
   my $href   = $req->uri_for_action( $self->moniker.'/column_view', $args );
   my $form   = $stash->{page}->{forms}->[ 0 ] = new_container 'column', $href;
   my $table  = $self->$_find_user_table( $req );
   my $column = $self->$_maybe_find_column( $table, $column_name );

   p_js $stash->{page}, set_element_focus 'column', 'name';

   p_textfield $form, 'name', $column->name, {
      class => 'standard-field required', label => 'user_column_name' };

   p_select $form, 'data_type', $_data_types->( $column ), {
      class => 'single-character required', };

   p_textfield $form, 'size', $column->size, {
      class => 'single-digit', label => 'user_column_size',
      label_class => 'clear' };

   p_textfield $form, 'default_value', $column->default_value;

   p_checkbox $form, 'nullable', TRUE, {
      checked => $column->nullable, label => 'nullable_column' };

   if ($column_name) {
      my $args = [ 'user_column', $column_name ];

      p_action $form, 'update', $args, { request => $req };
      p_action $form, 'delete', $args, { request => $req };
   }
   else { p_action $form, 'create', [ 'user_column' ], { request => $req } }

   return $stash;
}

sub create_user_column_action : Role(administrator) {
   my ($self, $req) = @_;

   my $table    = $self->$_find_user_table( $req );
   my $params   = $req->body_params;
   my $column   = $self->schema->resultset( 'UserColumn' )->create( {
      table_id      => $table->id,
      name          => $params->( 'name' ),
      nullable      => $params->( 'nullable' , { optional => TRUE } ) // FALSE,
      data_type     => $params->( 'data_type' ),
      default_value => $params->( 'default_value', { optional => TRUE } ),
      size          => $params->( 'size', { optional => TRUE } ),
   } );
   my $args     = [ $table->name ];
   my $message  = [ to_msg 'User column [_1] created by [_2]',
                    $column, $req->session->user_label ];
   my $location = $req->uri_for_action( $self->moniker.'/table_view', $args );

   return { redirect => { location => $location, message => $message } };
}

sub create_user_table_action : Role(administrator) {
   my ($self, $req) = @_;

   my $params   = $req->body_params;
   my $rs       = $self->schema->resultset( 'UserTable' );
   my $table    = $rs->create( { name => $params->( 'name' ) } );
   my $message  = [ to_msg 'User table [_1] created by [_2]',
                    $table, $req->session->user_label ];
   my $location = $req->uri_for_action( $self->moniker.'/table_list' );

   return { redirect => { location => $location, message => $message } };
}

sub delete_user_column_action : Role(administrator) {
   my ($self, $req) = @_;

   my $table  = $self->$_find_user_table( $req );
   my $name   = $req->uri_params->( 1 );
   my $rs     = $self->schema->resultset( 'UserColumn' );
   my $column = $rs->find( $table->id, $name )
      or throw 'User column [_1].[_2] unknown', [ $table->name, $name ];

   $column->delete;

   my $args     = [ $table->name ];
   my $location = $req->uri_for_action( $self->moniker.'/table_view', $args );
   my $message  = [ to_msg 'User column [_1] deleted by [_2]',
                    $column, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_user_table_action : Role(administrator) {
   my ($self, $req) = @_;

   my $table = $self->$_find_user_table( $req );

   $table->delete;

   my $message  = [ to_msg 'User table [_1] deleted by [_2]',
                    $table, $req->session->user_label ];
   my $location = $req->uri_for_action( $self->moniker.'/table_list' );

   return { redirect => { location => $location, message => $message } };
}

sub table_list : Role(administrator) {
   my ($self, $req) = @_;

   my $page = {
      selected => 'user_table_list',
      title    => locm $req, 'user_table_list_title'
   };
   my $form  = $page->{forms}->[ 0 ] = new_container;
   my $links = $self->$_tables_ops_links( $req );

   p_list $form, PIPE_SEP, $links, link_options 'right';

   my $table = p_table $form, { headers => $_tables_headers->( $req ) };
   my $table_rs = $self->schema->resultset( 'UserTable' );

   p_row $table, [ map { $self->$_tables_cells( $req, $_ ) } $table_rs->all ];

   p_list $form, PIPE_SEP, $links, link_options 'right';

   return $self->get_stash( $req, $page );
}

sub table_view : Role(administrator) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0, { optional => TRUE } );
   my $href   = $req->uri_for_action( $self->moniker.'/table_view', [ $name ] );
   my $form_a = new_container 'user-table', $href;
   my $form_b = new_container { class => 'wide-form' };
   my $page   = $_table_page->( $req, $form_a, $form_b );
   my $table  = $self->$_maybe_find_table( $name );

   p_textfield $form_a, 'name', $table->name, {
      disabled => $name ? TRUE : FALSE, label => 'user_table_name' };

   if ($name) {
      p_action $form_a, 'delete', [ 'user_table', $name ], { request => $req };
   }
   else { p_action $form_a, 'create', [ 'user_table' ], { request => $req } }

   $table->name or return $self->get_stash( $req, $page );

   p_tag $form_b, 'h5', locm $req, 'user_column_title';

   my $links = $self->$_column_ops_links( $req, $page, $table );

   p_list $form_b, PIPE_SEP, $links, link_options 'right';

   my $cols    = p_table $form_b, { headers => $_column_headers->( $req ) };
   my $cols_rs = $self->schema->resultset( 'UserColumn' );

   p_row $cols, [ map { $self->$_column_cells( $req, $page, $table, $_ ) }
                  $cols_rs->search( { table_id => $table->id } )->all ];

   p_list $form_b, PIPE_SEP, $links, link_options 'right';

   return $self->get_stash( $req, $page );
}

sub update_user_column_action : Role(administrator) {
   my ($self, $req) = @_;

   my $table  = $self->$_find_user_table( $req );
   my $name   = $req->uri_params->( 1 );
   my $params = $req->body_params;
   my $rs     = $self->schema->resultset( 'UserColumn' );
   my $column = $rs->find( $table->id, $name )
      or throw 'User column [_1].[_2] unknown', [ $table->name, $name ];

   $column->update( {
      data_type     => $params->( 'data_type' ),
      default_value => $params->( 'default_value', { optional => TRUE } ),
      size          => $params->( 'size', { optional => TRUE } ),
   } );

   my $args     = [ $table->name ];
   my $location = $req->uri_for_action( $self->moniker.'/table_view', $args );
   my $message  = [ to_msg 'User column [_1].[_2] updated by [_3]',
                    $table->name, $column->name, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::UserTable - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::UserTable;
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
