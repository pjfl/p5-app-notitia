package App::Notitia::Util;

use utf8;
use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Constants    qw( EXCEPTION_CLASS FALSE HASH_CHAR NUL SPC
                                   TILDE TRUE );
use Class::Usul::Crypt::Util   qw( decrypt_from_config encrypt_for_config );
use Class::Usul::File;
use Class::Usul::Functions     qw( class2appdir create_token
                                   ensure_class_loaded exception find_apphome
                                   first_char fold get_cfgfiles io is_arrayref
                                   is_hashref is_member throw );
use Class::Usul::Time          qw( str2date_time str2time time2str );
use Crypt::Eksblowfish::Bcrypt qw( en_base64 );
use Data::Validation;
use HTTP::Status               qw( HTTP_OK );
use JSON::MaybeXS;
use Scalar::Util               qw( blessed weaken );
use Try::Tiny;
use Unexpected::Functions      qw( ValidationErrors );
use YAML::Tiny;

our @EXPORT_OK = qw( action_for_uri assert_unique assign_link
                     authenticated_only build_navigation build_tree
                     check_field_js check_form_field clone datetime_label
                     dialog_anchor display_duration encrypted_attr enhance
                     event_actions event_handler event_handler_cache
                     get_hashed_pw get_salt is_access_authorised is_draft
                     is_encrypted iterator js_config js_slider_config
                     js_server_config js_submit_config js_togglers_config
                     js_window_config lcm_for load_file_data loc local_dt
                     localise_tree locd locm mail_domain make_id_from
                     make_name_from make_tip management_link mtime new_request
                     new_salt now_dt page_link_set register_action_paths
                     set_element_focus set_rota_date slot_claimed
                     slot_identifier slot_limit_index show_node stash_functions
                     time2int to_dt to_json to_msg uri_for_action );

# Private class attributes
my $action_path_uri_map = {}; # Key is an action path, value a partial URI
my $handler_cache       = {};
my $json_coder          = JSON::MaybeXS->new( utf8 => FALSE );
my $result_class_cache  = {};
my $translations        = {};
my $uri_action_path_map;      # Key is a partial URI, value an action path
my $yaml_coder          = YAML::Tiny->new;

# Private functions
my $check_field = sub {
   my ($schema, $req) = @_;

   my $params = $req->query_params;
   my $domain = $params->( 'domain' );
   my $class  = $params->( 'form'   );
   my $id     = $params->( 'id'     );
   my $val    = $params->( 'val', { raw => TRUE } );

   if (first_char $class eq '+') { $class = substr $class, 1 }
   else { $class = (blessed $schema)."::Result::${class}" }

   $result_class_cache->{ $class }
      or (ensure_class_loaded( $class )
          and $result_class_cache->{ $class } = TRUE);

   my $attr = $class->validation_attributes; $attr->{level} = 4;

   my $rs; $attr->{fields}->{ $id }->{unique} and $domain eq 'insert'
      and defined $val
      and $rs = $schema->resultset( $class )
      and assert_unique( $rs, { $id => $val }, $attr->{fields}, $id );

   return Data::Validation->new( $attr )->check_field( $id, $val );
};

my $extension2format = sub {
   my ($map, $path) = @_; my $extn = (split m{ \. }mx, $path)[ -1 ] // NUL;

   return $map->{ $extn } // 'text';
};

my $get_tip_text = sub {
   my ($conf, $node) = @_; my $path = $node->{path} or return NUL;

   my $root = $conf->docs_root;
   my $text = $path->abs2rel( $root ); $text =~ s{ \A [a-z]+ / }{}mx;
   my $posts = $conf->posts; $text =~ s{ \A $posts / }{}mx;

   $text =~ s{ \. .+ \z }{}mx; $text =~ s{ [/] }{ / }gmx;
   $text =~ s{ [_] }{ }gmx;

   return $text;
};

my $load_file_data = sub {
   load_file_data( $_[ 0 ] ); return TRUE;
};

my $page_link = sub {
   my ($req, $name, $actionp, $args, $params, $page) = @_;

   $params = { %{ $params } }; $params->{page} = $page;

   return { class => 'table-link',
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $actionp, $args, $params ),
            name  => $name,
            tip   => locm( $req, "${name}_tip", $page ),
            type  => 'link',
            value => locm( $req, "${name}_link", $page ), };
};

my $sorted_keys = sub {
   my $node = shift;

   return [ sort { $node->{ $a }->{_order} <=> $node->{ $b }->{_order} }
            grep { first_char $_ ne '_' } keys %{ $node } ];
};

my $make_tuple = sub {
   my $node = shift;

   ($node and exists $node->{type} and defined $node->{type})
      or return [ 0, [], $node ];

   my $keys = $node->{type} eq 'folder' ? $sorted_keys->( $node->{tree} ) : [];

   return [ 0, $keys, $node ];
};

my $vehicle_link = sub {
   my ($req, $page, $args, $opts) = @_;

   my $action = $opts->{action}; my $value = $opts->{value};

   my $path   = "asset/${action}"; my $params = { action => $action };

   $action eq 'unassign' and $params->{vehicle} = $value;
   $opts->{type} and $params->{type} = $opts->{type};

   my $href = uri_for_action( $req, $path, $args, $params );
   my $tip  = loc( $req, "${action}_management_tip" );
   my $js   = $page->{literal_js} //= [];
   my $name = $opts->{name};

   push @{ $js }, dialog_anchor( "${action}_${name}", $href, {
      name  => "${action}-vehicle",
      title => loc( $req, (ucfirst $action).' Vehicle' ), } );

   return { class => $opts->{class} // 'table-link windows',
            hint  => loc( $req, 'Hint' ),
            href  => HASH_CHAR,
            name  => "${action}_${name}",
            tip   => $tip,
            type  => 'link',
            value => (blessed $value) ? $value->slotref : $value, };
};

# Public functions
sub action_for_uri ($) {
   my $uri = shift; $uri or return;

   unless ($uri_action_path_map) {
      for my $actionp (keys %{ $action_path_uri_map }) {
         my $key = $action_path_uri_map->{ $actionp };

         $key and $uri_action_path_map->{ $key } = $actionp;
      }
   }

   my @parts = split m{ / }mx, $uri;

   while (@parts) {
      my $key = join '/', @parts; my $actionp = $uri_action_path_map->{ $key };

      $actionp and return $actionp; pop @parts;
   }

   return;
}

sub assert_unique ($$$$) {
   my ($rs, $columns, $fields, $k) = @_;

   defined $columns->{ $k } or return;
   is_arrayref $fields->{ $k }->{unique} and return;
   defined( ($rs->search( { $k => $columns->{ $k } } )->all)[ 0 ] ) or return;

   my $v = $columns->{ $k }; length $v > 10 and $v = substr( $v, 0, 10 ).'...';
   my $e = exception 'Parameter [_1] is not unique ([_2])', [ $k, $v ];

   throw ValidationErrors, [ $e ], level => 2;
}

sub assign_link ($$$$) {
   my ($req, $page, $args, $opts) = @_; my $type = $opts->{type};

   my $name = $opts->{name}; my $value = $opts->{vehicle};

   my $state = slot_claimed( $opts ) ? 'vehicle-not-needed' : NUL;

   $opts->{vehicle_req} and $state = 'vehicle-requested';
   $value and $state = 'vehicle-assigned';

   if ($state eq 'vehicle-assigned') {
      my $opts = { action => 'unassign', name => $name, value => $value };

      $value = $vehicle_link->( $req, $page, $args, $opts );
   }
   elsif ($state eq 'vehicle-requested') {
      my $opts = { action => 'assign',
                   class => 'table-link vehicle-requested windows',
                   name  => $name, value => 'requested' };

      $type and $opts->{type} = $type;
      $value = $vehicle_link->( $req, $page, $args, $opts );
   }

   my $style; $state eq 'vehicle-assigned' and $opts->{vehicle}->colour
      and $style = 'background-color: '.$opts->{vehicle}->colour.';';

   my $class = "centre narrow ${state}";

   return { class => $class, style => $style, value => $value };
}

sub authenticated_only ($) {
   my $conf = shift; my $assets = $conf->assets;

   return sub {
      $_ =~ m{ \A / $assets         }mx or  return FALSE;
      $_ =~ m{ \A / $assets /public }mx and return TRUE;

      my $sess = $_[ 1 ]->{ 'psgix.session' };

      $sess->{authenticated} or return FALSE;

      $_ =~ m{ \A / $assets /personal }mx or return TRUE;

      for my $role (@{ $conf->asset_manager }) {
         is_member $role, $sess->{roles} and return TRUE;
      }

      return FALSE;
   };
}

sub build_navigation ($$) {
   my ($req, $opts) = @_; my $count = 0; my @nav = ();

   my $ids = $req->uri_params->() // []; my $iter = iterator( $opts->{node} );

   while (defined (my $node = $iter->())) {
      $node->{id} eq 'index' and next;
      is_access_authorised( $req, $node ) or next;

      if ($node->{type} eq 'folder') {
         my $keepit = FALSE; $node->{fcount} < 1 and next;

         for my $id (grep { not m{ \A _ }mx } keys %{ $node->{tree} }) {
            is_access_authorised( $req, $node->{tree}->{ $id } )
               and $keepit = TRUE and last;
         }

         $keepit or next;
      }

      my $link = clone( $node ); delete $link->{tree};

      $link->{class}  = $node->{type} eq 'folder' ? 'folder-link' : 'file-link';
      $link->{depth} -= $opts->{depth_offset};
      $link->{href }  = uri_for_action( $req, $opts->{path}, [ $link->{url} ] );
      $link->{tip  }  = $get_tip_text->( $opts->{config}, $node );
      $link->{value}  = $opts->{label}->( $link );

      if (defined $ids->[ 0 ] and $ids->[ 0 ] eq $node->{id}) {
         $link->{class} .= ' open'; shift @{ $ids };
         defined $ids->[ 0 ] or $link->{class} .= ' selected';
      }

      push @nav, $link;
      $opts->{limit} and $node->{type} eq 'file'
         and ++$count >= $opts->{limit} and last;
   }

   return \@nav;
}

sub build_tree {
   my ($map, $dir, $depth, $node_order, $url_base, $parent) = @_;

   $depth //= 0; $node_order //= 0; $url_base //= NUL; $parent //= NUL;

   my $fcount = 0; my $max_mtime = 0; my $tree = {}; $depth++;

   for my $path (grep { defined $_->stat } $dir->all) {
      my ($id, $pref) =  @{ make_id_from( $path->utf8->filename ) };
      my  $name       =  make_name_from( $id );
      my  $url        =  $url_base ? "${url_base}/${id}" : $id;
      my  $mtime      =  $path->stat->{mtime} // 0;
      my  $node       =  $tree->{ $id } = {
          depth       => $depth,
          format      => $extension2format->( $map, "${path}" ),
          id          => $id,
          modified    => $mtime,
          name        => $name,
          parent      => $parent,
          path        => $path,
          prefix      => $pref,
          title       => ucfirst $name,
          type        => 'file',
          url         => $url,
          _order      => $node_order++, };

      $path->is_file and ++$fcount and $load_file_data->( $node )
                     and $mtime > $max_mtime and $max_mtime = $mtime;
      $path->is_dir  or  next;
      $node->{type} = 'folder';
      $node->{tree} = $depth > 1 # Skip the language code directories
         ?  build_tree( $map, $path, $depth, $node_order, $url, $name )
         :  build_tree( $map, $path, $depth, $node_order );
      $fcount += $node->{fcount} = $node->{tree}->{_fcount};
      mtime( $node ) > $max_mtime and $max_mtime = mtime( $node );
   }

   $tree->{_fcount} = $fcount; $tree->{_mtime} = $max_mtime;

   return $tree;
}

sub check_field_js ($$) {
   my ($k, $opts) = @_; my $args = [ $k, $opts->{form}, $opts->{domain} ];

   return js_server_config( $k, 'blur', 'checkField', $args );
}

sub check_form_field ($$;$) {
   my ($schema, $req, $log) = @_; my $mesg;

   my $id = $req->query_params->( 'id' ); my $meta = { id => "${id}_ajax" };

   try   { $check_field->( $schema, $req ) }
   catch {
      my $e = $_;

      $log and $log->debug( "${e}" );
      $mesg = $req->loc( $e->error, { params => $e->args } );
      $meta->{class_name} = 'field-error';
   };

   return { code => HTTP_OK,
            page => { content => { html => $mesg }, meta => $meta },
            view => 'json' };
}

sub clone (;$) {
   my $v = shift;

   is_arrayref $v and return [ @{ $v // [] } ];
   is_hashref  $v and return { %{ $v // {} } };
   return $v;
}

sub datetime_label ($) {
   my $dt = shift; $dt or return NUL; $dt = local_dt( $dt );

   return sprintf '%s @ %.2d:%.2d', $dt->dmy( '/' ), $dt->hour, $dt->minute;
}

sub dialog_anchor ($$$) {
   my ($k, $href, $opts) = @_;

   exists $opts->{useIcon} or $opts->{useIcon} = \1;

   return js_window_config( $k, 'click', 'modalDialog', [ "${href}", $opts ] );
}

sub display_duration ($$) {
   my ($req, $event) = @_; my ($start, $end) = $event->duration;

   $start = $start->set_time_zone( 'local' );
   $end = $end->set_time_zone( 'local' );

   return
   loc( $req, 'Starts' ).SPC.$start->dmy( '/' ).SPC.$start->strftime( '%H:%M' ),
   loc( $req, 'Ends' ).SPC.$end->dmy( '/' ).SPC.$end->strftime( '%H:%M' );
}

sub encrypted_attr ($$$$) {
   my ($conf, $file, $k, $default) = @_; my $data = {}; my $v;

   if ($file->exists) {
      $data = Class::Usul::File->data_load( paths => [ $file ] ) // {};
      $v    = decrypt_from_config $conf, $data->{ $k };
   }

   unless ($v) {
      $data->{ $k } = encrypt_for_config $conf, $v = $default->();
      Class::Usul::File->data_dump( { path => $file->assert, data => $data } );
   }

   return $v;
}

sub enhance ($) {
   my $conf = shift;
   my $attr = { config => { %{ $conf } }, }; $conf = $attr->{config};

   $conf->{appclass    } //= 'App::Notitia';
   $attr->{config_class} //= $conf->{appclass}.'::Config';
   $conf->{name        } //= class2appdir $conf->{appclass};
   $conf->{home        } //= find_apphome $conf->{appclass}, $conf->{home};
   $conf->{cfgfiles    } //= get_cfgfiles $conf->{appclass}, $conf->{home};

   return $attr;
}

sub event_actions ($) {
   return sort grep { not m{ \A _ }mx } keys %{ $handler_cache->{ $_[ 0 ] } };
}

sub event_handler ($$;&) {
   my ($stream, $action, $handler) = @_;

   $handler_cache->{ $stream }->{ $action } //= [];

   defined $handler
       and push @{ $handler_cache->{ $stream }->{ $action } }, $handler;

   return $handler_cache->{ $stream }->{ $action };
};

sub event_handler_cache () {
   return { %{ $handler_cache } };
}

sub gcf ($$) {
   my ($x, $y) = @_; ($x, $y) = ($y, $x % $y) while ($y); return $x;
}

sub get_hashed_pw ($) {
   my @parts = split m{ [\$] }mx, $_[ 0 ]; return substr $parts[ -1 ], 22;
}

sub get_salt ($) {
   my @parts = split m{ [\$] }mx, $_[ 0 ];

   $parts[ -1 ] = substr $parts[ -1 ], 0, 22;

   return join '$', @parts;
}

sub is_access_authorised ($$) {
   my ($req, $node) = @_; $node->{type} eq 'folder' and return TRUE;

   my $nroles = $node->{role} // $node->{roles};

   $nroles = is_arrayref( $nroles ) ? $nroles : $nroles ? [ $nroles ] : [];

   is_member( 'anon', $nroles ) and return TRUE;
   $req->authenticated or return FALSE;
   is_member( 'any',  $nroles ) and return TRUE;

   my $proles = $req->session->roles;

   is_member 'editor', $proles and return TRUE;

   $node->{author} and $req->username eq $node->{author} and return TRUE;

   for my $role (@{ $nroles }) { is_member $role, $proles and return TRUE }

   return FALSE;
}

sub is_draft ($$) {
   my ($conf, $url) = @_; my $drafts = $conf->drafts; my $posts = $conf->posts;

   $url =~ m{ \A $drafts \b }mx and return TRUE;
   $url =~ m{ \A $posts / $drafts \b }mx and return TRUE;

   return FALSE;
}

sub is_encrypted ($) {
   return $_[ 0 ] =~ m{ \A \$\d+[a]?\$ }mx ? TRUE : FALSE;
}

sub iterator ($) {
   my $tree = shift; my @folders = ( $make_tuple->( $tree ) );

   return sub {
      while (my $tuple = $folders[ 0 ]) {
         while (defined (my $k = $tuple->[ 1 ]->[ $tuple->[ 0 ]++ ])) {
            my $node = $tuple->[ 2 ]->{tree}->{ $k };

            $node->{type} eq 'folder'
               and unshift @folders, $make_tuple->( $node );

            return $node;
         }

         shift @folders;
      }

      return;
   };
}

sub js_config ($$$) { # Deprecated
   my ($page, $name, $params) = @_;

   my $k      = $params->[ 0 ];
   my $event  = $params->[ 1 ];
   my $method = $params->[ 2 ];
   my $args   = $json_coder->encode( $params->[ 3 ] );

   return push @{ $page->{literal_js} //= [] },
        "   behaviour.config.${name}[ '${k}' ] = {",
        "      event     : '${event}',",
        "      method    : '${method}',",
        "      args      : ${args} };";
}

sub js_server_config ($$$$) {
   my ($k, $event, $method, $args) = @_; $args = $json_coder->encode( $args );

   return "   behaviour.config.server[ '${k}' ] = {",
          "      event     : '${event}',",
          "      method    : '${method}',",
          "      args      : ${args} };";
}

sub js_slider_config ($$$) {
   my ($page, $k, $params) = @_; $params = $json_coder->encode( $params );

   return push @{ $page->{literal_js} //= [] },
        "   behaviour.config.slider[ '${k}' ] = ${params};";
}

sub js_submit_config ($$$$) {
   my ($k, $event, $method, $args) = @_; $args = $json_coder->encode( $args );

   return "   behaviour.config.submit[ '${k}' ] = {",
          "      event     : '${event}',",
          "      method    : '${method}',",
          "      args      : ${args} };";
}

sub js_togglers_config ($$$$) {
   my ($k, $event, $method, $args) = @_; $args = $json_coder->encode( $args );

   return "   behaviour.config.togglers[ '${k}' ] = {",
          "      event     : '${event}',",
          "      method    : '${method}',",
          "      args      : ${args} };";
}

sub js_window_config ($$$$) {
   my ($k, $event, $method, $args) = @_; $args = $json_coder->encode( $args );

   return "   behaviour.config.window[ '${k}' ] = {",
          "      event     : '${event}',",
          "      method    : '${method}',",
          "      args      : ${args} };";
}

sub lcm ($$) {
   return $_[ 0 ] * $_[ 1 ] / gcf( $_[ 0 ], $_[ 1 ] );
}

sub lcm_for (@) {
   return ((fold { lcm $_[ 0 ], $_[ 1 ] })->( shift ))->( @_ );
}

sub load_file_data {
   my $node = shift; my $body = $node->{path}->all;

   my $yaml; $body =~ s{ \A --- $ ( .* ) ^ --- $ }{}msx and $yaml = $1;

   $yaml or return $body; my $data = $yaml_coder->read_string( $yaml )->[ 0 ];

   exists $data->{created} and $data->{created} = str2time $data->{created};

   $node->{ $_ } = $data->{ $_ } for (keys %{ $data });

   return $body;
}

sub loc ($@) {
   my ($req, @args) = @_; my $k = shift @args;

   $translations->{ my $locale = $req->locale } //= {};

   return exists $translations->{ $locale }->{ $k }
               ? $translations->{ $locale }->{ $k }
               : $translations->{ $locale }->{ $k } = $req->loc( $k, @args );
}

sub local_dt ($) {
   defined $_[ 0 ] or throw 'Datetime object undefined', level => 2;

   return $_[ 0 ]->clone->set_time_zone( 'local' );
}

sub localise_tree ($$) {
   my ($tree, $locale) = @_; ($tree and $locale) or return FALSE;

   exists $tree->{ $locale } and defined $tree->{ $locale }
      and return $tree->{ $locale };

   return FALSE;
}

sub locd ($$) {
   my $req = shift; return local_dt( $_[ 0 ] )->dmy( '/' );
}

sub locm ($@) {
   my $req = shift; return loc $req, to_msg( @_ );
}

sub mail_domain () {
   my $mailname_path = io[ NUL, 'etc', 'mailname' ]; my $domain = 'example.com';

   $mailname_path->exists and $domain = $mailname_path->chomp->getline;

   return $domain;
}

sub make_id_from ($) {
   my $v = shift; my ($p) = $v =~ m{ \A ((?: \d+ [_\-] )+) }mx;

   $v =~ s{ \A (\d+ [_\-])+ }{}mx; $v =~ s{ [_] }{-}gmx;

   $v =~ s{ \. [a-zA-Z0-9\-\+]+ \z }{}mx;

   defined $p and $p =~ s{ [_\-]+ \z }{}mx;

   return [ $v, $p // NUL ];
}

sub make_name_from ($) {
   my $v = shift; $v =~ s{ [_\-] }{ }gmx; return $v;
}

sub make_tip ($$;$) {
   my ($req, $k, $args) = @_;

   return loc( $req, 'Hint' ).SPC.TILDE.SPC
        . locm( $req, $k, map  { my $x = $_; $x =~ s{_}{ }gmx; $x }
                          grep { defined } @{ $args // [] } );
}

sub management_link ($$$;$) {
   my ($req, $actionp, $name, $opts) = @_; $opts //= {};

   my $args   = $opts->{args} // [ $name ];
   my $params = $opts->{params} // {};
   my ($moniker, $method) = split m{ / }mx, $actionp, 2;
   my $href   = uri_for_action( $req, $actionp, $args, $params );
   my $type   = $opts->{type} // 'link';
   my $button = { class => 'table-link',
                  hint  => loc( $req, 'Hint' ),
                  href  => $href,
                  name  => "${name}-${method}",
                  tip   => locm( $req, "${method}_management_tip", @{ $args } ),
                  type  => $type,
                  value => loc( $req, "${method}_management_link" ), };

   if ($type eq 'form_button') {
      $button->{form_name} = "${name}-${method}";
      $button->{label    } = loc( $req, "${name}_${method}_link" );
      $button->{tip      } = locm( $req, "${name}_${method}_tip", @{ $args } );
      $button->{value    } = "${name}_${method}";
   }

   return $button;
}

sub mtime ($) {
   return $_[ 0 ]->{tree}->{_mtime};
}

sub new_request ($$$$) {
   my ($conf, $locale, $scheme, $hostport) = @_;

   ensure_class_loaded 'Web::ComposableRequest';

   my $env = { HTTP_ACCEPT_LANGUAGE => $locale,
               HTTP_HOST => $hostport // 'localhost:5000',
               SCRIPT_NAME => $conf->mount_point,
               'psgi.url_scheme' => $scheme // 'http',
               'psgix.session' => { username => 'admin' } };
   my $factory = Web::ComposableRequest->new( config => $conf );

   return $factory->new_from_simple_request( {}, '', {}, $env );
}

sub new_salt ($$) {
   my ($type, $lf) = @_;

   return "\$${type}\$${lf}\$"
        . (en_base64( pack( 'H*', substr( create_token, 0, 32 ) ) ) );
}

sub now_dt () {
   return to_dt( time2str );
}

sub page_link_set ($$$$$;$) {
   my ($req, $actionp, $args, $params, $pager, $opts) = @_;

   $pager->last_page > $pager->first_page or return;

   my $list = [ $page_link->( $req, 'first_page', $actionp,
                              $args, $params, $pager->first_page ) ];
   my $lower_b = $pager->current_page - 4;
   my $page = $lower_b < $pager->first_page ? $pager->first_page : $lower_b;

   while (++$page < $pager->current_page) {
      push @{ $list }, $page_link->( $req, 'earlier_page', $actionp,
                                     $args, $params, $page );
   }

   push @{ $list }, $page_link->( $req, 'current_page', $actionp, $args,
                                  $params, $pager->current_page );

   my $upper_b = $pager->current_page + 4;

   $upper_b = $upper_b > $pager->last_page ? $pager->last_page : $upper_b;
   $page = $pager->current_page;

   while (++$page < $upper_b) {
       push @{ $list }, $page_link->( $req, 'later_page', $actionp,
                                      $args, $params, $page );
   }

   push @{ $list }, $page_link->( $req, 'last_page', $actionp, $args,
                                  $params, $pager->last_page );

   return { class        => $opts->{class} // 'link-group',
            content      => {
               list      => $list,
               separator => ' ',
               type      => 'list', },
            type         => 'container', };
}

sub register_action_paths (;@) {
   my $args = (is_hashref $_[ 0 ]) ? $_[ 0 ] : { @_ };

   for my $k (keys %{ $args }) { $action_path_uri_map->{ $k } = $args->{ $k } }

   return;
}

sub set_element_focus ($$) {
   my ($form, $name) = @_;

   return [ "var form = document.forms[ '${form}' ];",
            "var f = function() { behaviour.rebuild(); form.${name}.focus() };",
            'f.delay( 100 );', ];
}

sub set_rota_date ($$$$) {
   my ($parser, $where, $key, $opts) = @_;

   if (my $after = delete $opts->{after}) {
      $where->{ $key }->{ '>' } = $parser->format_datetime( $after );
      $opts->{order_by} //= $key;
   }

   if (my $before = delete $opts->{before}) {
      $where->{ $key }->{ '<' } = $parser->format_datetime( $before );
   }

   if (my $ondate = delete $opts->{on}) {
      $where->{ $key } = $parser->format_datetime( $ondate );
   }

   return;
}

sub show_node ($;$$) {
   my ($node, $wanted, $wanted_depth) = @_;

   $wanted //= NUL; $wanted_depth //= 0;

   return $node->{depth} >= $wanted_depth
       && $node->{url  } =~ m{ \A $wanted }mx ? TRUE : FALSE;
}

sub slot_claimed ($) {
   return defined $_[ 0 ] && exists $_[ 0 ]->{operator} ? TRUE : FALSE;
}

sub slot_identifier ($$@) {
   my ($rota_name, $rota_date, $shift_type, $slot_type, $subslot) = @_;

   $rota_name =~ s{ _ }{ }gmx;

   return sprintf '%s rota on %s %s shift %s slot %s',
          ucfirst( $rota_name ), $rota_date, $shift_type, $slot_type, $subslot;
}

sub slot_limit_index ($$) {
   my ($shift_type, $slot_type) = @_;

   my $shift_map = { day => 0, night => 1 };
   my $slot_map  = { controller => 0, driver => 4, rider => 2 };

   return $shift_map->{ $shift_type } + $slot_map->{ $slot_type };
}

sub stash_functions ($$$) {
   my ($app, $req, $dest) = @_; weaken $req;

   $dest->{is_member     } = \&is_member;
   $dest->{loc           } = sub { loc( $req, shift, @_ ) };
   $dest->{reference     } = sub { ref $_[ 0 ] };
   $dest->{show_node     } = \&show_node;
   $dest->{str2time      } = \&str2time;
   $dest->{time2str      } = \&time2str;
   $dest->{ucfirst       } = sub { ucfirst $_[ 0 ] };
   $dest->{uri_for       } = sub { $req->uri_for( @_ ), };
   $dest->{uri_for_action} = sub { uri_for_action( $req, @_ ), };
   return;
}

sub to_json ($) {
   return $json_coder->encode( $_[ 0 ] );
}

sub time2int ($) {
   my $x = shift; $x or $x = 0; $x =~ s{ : }{}mx; return $x;
}

sub to_dt ($;$) {
   my ($dstr, $zone) = @_;

   my $dt = ($zone and $zone ne 'local') ? str2date_time( $dstr, $zone )
                                         : str2date_time( $dstr );

   $zone and $zone eq 'local' and $dt->set_time_zone( 'local' );

   return $dt;
}

sub to_msg (@) {
   my $k = shift; return $k, { no_quote_bind_values => TRUE, params => [ @_ ] };
}

sub uri_for_action ($$;@) {
   my ($req, $action, @args) = @_;

   blessed $req or throw 'Not a request object [_1]', [ $req ];

   my $uri = $action_path_uri_map->{ $action } // $action;

   $uri =~ m{ \* }mx or return $req->uri_for( $uri, @args );

   my $args = shift @args;

   while ($uri =~ m{ \* }mx) {
      my $arg = (shift @{ $args }) || q(); $uri =~ s{ \* }{$arg}mx;
   }

   unshift @args, $args;

   return $req->uri_for( $uri, @args );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Util - Functions used in this application

=head1 Synopsis

   use App::Notitia::Util qw( uri_for_action );

   my $uri = uri_for_action $req, $action_path, $args, $params;

=head1 Description

Functions used in this application

=head1 Configuration and Environment

Defines no attributes

=head1 Subroutines/Methods

=head2 C<action_for_uri>

=head2 C<assert_unique>

=head2 C<assign_link>

=head2 C<authenticated_only>

=head2 C<build_navigation>

=head2 C<build_tree>

=head2 C<check_field_js>

=head2 C<check_form_field>

=head2 C<clone>

=head2 C<datetime_label>

=head2 C<dialog_anchor>

=head2 C<display_duration>

=head2 C<encrypted_attr>

=head2 C<enhance>

=head2 C<event_actions>

=head2 C<event_handler>

=head2 C<event_handler_cache>

=head2 C<gcf>

Greatest common factor

=head2 C<get_hashed_pw>

=head2 C<get_salt>

=head2 C<is_access_authorised>

=head2 C<is_draft>

=head2 C<is_encrypted>

=head2 C<iterator>

=head2 C<js_config>

=head2 C<js_server_config>

=head2 C<js_slider_config>

=head2 C<js_submit_config>

=head2 C<js_togglers_config>

=head2 C<js_window_config>

=head2 C<lcm>

Least common muliple

=head2 C<lcm_for>

LCM for a list of integers

=head2 C<load_file_data>

=head2 C<loc>

=head2 C<local_dt>

=head2 C<localise_tree>

=head2 C<locd>

=head2 C<locm>

=head2 C<mail_domain>

=head2 C<make_id_from>

=head2 C<make_name_from>

=head2 C<make_tip>

=head2 C<management_link>

=head2 C<mtime>

=head2 C<new_request>

=head2 C<new_salt>

=head2 C<now_dt>

=head2 C<page_link_set>

=head2 C<register_action_paths>

   register_action_paths $action_path => $partial_uri;

Used by L</uri_for_action> to lookup the partial URI for the action path
prior to calling the L<uri_for|Web::ComposableRequest::Base/uri_for> method
on the request object

=head2 C<set_element_focus>

=head2 C<set_rota_date>

=head2 C<show_node>

=head2 C<slot_claimed>

=head2 C<slot_identifier>

=head2 C<slot_limit_index>

=head2 C<stash_functions>

=head2 C<time2int>

=head2 C<to_dt>

=head2 C<to_json>

=head2 C<to_msg>

=head2 C<uri_for_action>

   !uri = uri_for_action !request, $action_path, \@uri_args, \%query_params;

Looks up the action path in the map created by calls to
L</register_action_path>.  It then calls the
L<uri_for|Web::ComposableRequest::Base/uri_for> method which is provided by the
request object. Returns a L<URI> object reference

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<strictures>

=item L<Class::Usul>

=item L<Crypt::Eksblowfish::Bcrypt>

=item L<Data::Validation>

=item L<Exporter::Tiny>

=item L<HTTP::Status>

=item L<JSON::MaybeXS>

=item L<Try::Tiny>

=item L<YAML::Tiny>

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
