package App::Notitia::Model::Management;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE HASH_CHAR NUL PIPE_SEP SPC TRUE );
use App::Notitia::DOM       qw( new_container p_cell p_item p_js p_link p_list
                                p_row p_table );
use App::Notitia::Util      qw( add_dummies build_navigation build_tree
                                dialog_anchor link_options locm
                                register_action_paths to_dt );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Types      qw( NonZeroPositiveInt PositiveInt );
use English                 qw( -no_match_vars );
use Moo;

extends q(App::Notitia::Model);

# Public attributes
has '+moniker' => default => 'manage';

has 'depth_offset' => is => 'ro', isa => PositiveInt, default => 1;

has 'max_navigation' => is => 'ro', isa => NonZeroPositiveInt, default => 1000;

with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::Navigation);
with    q(App::Notitia::Role::PageLoading);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Editor);

register_action_paths
   'manage/dialog' => 'management-dialog',
   'manage/template_view' => 'email-template',
   'manage/template_list' => 'email-templates',
   'manage/form_list' => 'forms',
   'manage/form_view' => 'form',
   'manage/index'  => 'management-index';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args ); add_dummies $stash;

   $stash->{page}->{selected} //= 'email_templates';
   $stash->{page}->{location} //= 'management';
   $stash->{navigation}
      = $self->management_navigation_links( $req, $stash->{page} );

   return $stash;
};

my $_docs_cache = { _mtime => 0, };

my $_form_list_headers = sub {
   my $req = shift; my $header = 'form_list_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 0 ];
};

my $_template_list_headers = sub {
   my $req = shift; my $header = 'email_templates_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 2 ];
};

my $_template_list_row = sub {
   my $template = shift; $template->{type} = 'link';

   return [ { value => $template },
            { value => $template->{subject} },
            { value => $template->{author} } ]
};

my $_form_list_cells = sub {
   my ($self, $req, $form) = @_; my $cells = [];

   my $args = [ $form->name ];
   my $href = $req->uri_for_action( $self->moniker.'/form_view', $args );

   p_item $cells, p_link {}, 'user_form_fill', $href, {
      request => $req, value => $form->name };

   return $cells;
};

my $_template_list_ops_links = sub {
   my ($self, $req, $page) = @_; my $links = [];

   my $params = { name => 'create' };
   my $href = $req->uri_for_action( $self->moniker.'/dialog', [], $params );
   my $name = 'email_template';

   p_link $links, $name, HASH_CHAR, {
      action => 'create', class => 'windows', container_class => 'add-link',
      request => $req };

   p_js $page, dialog_anchor "create_${name}", $href, {
      title => locm $req, 'Create File',
   };

   return $links;
};

sub base_uri {
   return $_[ 1 ]->uri_for_action( $_[ 0 ]->moniker.'/template_view', $_[ 2 ] );
}

sub cancel_edit_action : Role(anon) {
   return { redirect => { location => $_[ 1 ]->uri_no_query } };
}

sub create_file_action : Role(editor) Role(person_manager) {
   return $_[ 0 ]->create_file( $_[ 1 ] );
}

sub delete_file_action : Role(editor) Role(person_manager) {
   my ($self, $req) = @_; my $stash = $self->delete_file( $req );

   $stash->{redirect}->{location}
      = $req->uri_for_action( $self->moniker.'/template_list' );

   return $stash;
}

sub dialog : Dialog Role(editor) Role(person_manager) {
   return $_[ 0 ]->get_dialog( $_[ 1 ] );
}

sub form_list : Role(administrator) {
   my ($self, $req) = @_;

   my $form = new_container { class => 'standard-form' };
   my $page = {
      forms    => [ $form ],
      selected => 'form_list',
      title    => locm $req, 'form_list_title'
   };
   my $table = p_table $form, { headers => $_form_list_headers->( $req ) };
   my $form_rs = $self->schema->resultset( 'UserForm' );

   p_row $table, [ map { $self->$_form_list_cells( $req, $_ ) } $form_rs->all ];

   return $self->get_stash( $req, $page );
}

sub form_view : Role(administrator) {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0 );
   my $preview = $req->query_params->( 'preview', { optional => TRUE } );
   my $rs      = $self->schema->resultset( 'UserForm' );
   my $form    = $rs->search( { name => $name } )->first
      or throw 'User form [_1] not found', [ $name ];
   my $href    = $req->uri_for_action( $self->moniker.'/form_view', [ $name ] );
   my $form_0  = new_container "${name}-form", $href, { class => 'wide-form' };
   my $page    = {
      css      => $form->content( 'css' ),
      forms    => [ $form_0 ],
      preview  => $preview ? TRUE : FALSE,
      selected => 'form_list',
      template => [ $preview ? 'none' : '/menu', $form->template ],
      title    => $form->content( 'title' ),
   };
   my $field_rs = $self->schema->resultset( 'UserField' );

   for my $field ($field_rs->search( { form_id => $form->id }, {
      order_by => 'order' } )->all) {
      p_cell $form_0->{content}->{list}, {
         class       => $field->class,
         container_class => $field->container_class,
         disabled    => $field->disabled,
         fieldsize   => $field->fieldsize,
         label       => $field->label // $field->name,
         label_class => $field->label_class,
         maxlength   => $field->maxlength,
         name        => $field->name,
         placeholder => $field->placeholder,
         tip         => $field->tip ? make_tip( $req, $field->tip, [] ) : FALSE,
         type        => $field->field_type,
         value       => $field->value,
      };
   }

   my $stash = $self->get_stash( $req, $page );

   $preview and $stash->{navigation} = {};

   return $stash;
}

sub index : Role(administrator) Role(address_viewer) Role(controller)
            Role(editor) Role(person_manager) Role(rota_manager) {
   my ($self, $req) = @_;

   my $page = {
      selected => NUL,
      title => locm $req, 'management_index_title'
   };

   return $self->get_stash( $req, $page );
}

sub localised_tree {
   return { tree => $_[ 0 ]->tree_root, type => 'folder' };
}

sub nav_label {
   return sub { my ($req, $link) = @_; $link->{title} };
}

sub qualify_path {
   my ($self, $locale, @pathname) = @_;

   my $opts = pop @pathname; my $conf = $self->config;

   $opts->{draft} and unshift @pathname, $self->config->drafts;

   return $conf->template_dir->catdir
      ( $conf->email_templates )->catfile( @pathname )->utf8;
}

sub rename_file_action : Role(editor) Role(person_manager) {
   return $_[ 0 ]->rename_file( $_[ 1 ] );
}

sub save_file_action : Role(editor) Role(person_manager) {
   return $_[ 0 ]->save_file( $_[ 1 ] );
}

sub search : Role(any) {
   return $_[ 0 ]->search_files( $_[ 1 ] );
}

sub template_list : Role(editor) Role(person_manager) {
   my ($self, $req) = @_;

   my $form    =  new_container 'email-templates', { class => 'wide-form' };
   my $page    =  {
      forms    => [ $form ],
      selected => 'email_templates',
      title    => locm $req, 'email_templates_title',
   };
   my $links   =  $self->$_template_list_ops_links( $req, $page );

   p_list $form, PIPE_SEP, $links, link_options 'right';

   my $nav = build_navigation $req, {
      config       => $self->config,
      depth_offset => $self->depth_offset,
      label        => $self->nav_label,
      limit        => $self->max_navigation,
      node         => $self->localised_tree,
      path         => $self->moniker.'/template_view',
   };
   my $table = p_table $form, {
      headers => $_template_list_headers->( $req ) };

   p_row $table, [ map  { $_template_list_row->( $_ ) }
                   grep { $_->{type} eq 'file' and $_->{path} =~ m{ \.md }mx }
                       @{ $nav } ];

   return $self->get_stash( $req, $page );
}

sub template_view : Role(editor) Role(person_manager) {
   my ($self, $req) = @_;

   my $stash = $self->get_stash( $req );
   my $skin  = $req->session->skin || $self->config->skin;

   $stash->{page}->{template}->[ 1 ] = "${skin}/documentation";

   return $stash;
}

sub tree_root {
   my $self = shift; my $mtime = $self->docs_mtime_cache;

   if ($mtime == 0 or $mtime > $_docs_cache->{_mtime}) {
      my $conf     = $self->config;
      my $no_index = join '|', @{ $conf->no_index };
      my $filter   = sub { not m{ (?: $no_index ) }mx };
      my $dir      = $conf->template_dir->catdir( $conf->email_templates );

      $self->log->info( "Tree building ${dir} ${PID}" );
      $_docs_cache = build_tree( $self->type_map, $dir->filter( $filter ) );
      $_docs_cache->{_mtime} > $mtime and $mtime = $_docs_cache->{_mtime};
      $self->docs_mtime_cache( $_docs_cache->{_mtime} = $mtime );
   }

   return $_docs_cache;
}

1;
