package App::Notitia::Util;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Constants    qw( FALSE HASH_CHAR NUL SPC TILDE TRUE
                                   VARCHAR_MAX_SIZE );
use Class::Usul::Functions     qw( class2appdir create_token
                                   ensure_class_loaded find_apphome
                                   first_char get_cfgfiles is_arrayref
                                   is_hashref is_member throw );
use Class::Usul::Time          qw( str2date_time str2time time2str );
use Crypt::Eksblowfish::Bcrypt qw( en_base64 );
use Data::Validation;
use DateTime                   qw( );
use HTTP::Status               qw( HTTP_OK );
use JSON::MaybeXS;
use Scalar::Util               qw( blessed weaken );
use Try::Tiny;
use YAML::Tiny;

our @EXPORT_OK = qw( admin_navigation_links assign_link bind bind_fields
                     bool_data_type build_navigation build_tree button
                     check_field_server check_form_field clone create_link
                     date_data_type delete_button dialog_anchor
                     enumerated_data_type enhance field_options
                     foreign_key_data_type get_hashed_pw get_salt is_draft
                     is_encrypted iterator loc localise_tree make_id_from
                     make_name_from make_tip management_link mtime new_salt
                     nullable_foreign_key_data_type nullable_varchar_data_type
                     numerical_id_data_type register_action_paths
                     rota_navigation_links save_button serial_data_type
                     set_element_focus set_on_create_datetime_data_type
                     slot_claimed slot_identifier slot_limit_index show_node
                     stash_functions table_link uri_for_action
                     varchar_data_type );

# Private class attributes
my $action_path_uri_map = {}; # Key is an action path, value a partial URI
my $field_option_cache  = {};
my $json_coder          = JSON::MaybeXS->new( utf8 => FALSE );
my $result_class_cache  = {};
my $translations        = {};
my $yaml_coder          = YAML::Tiny->new;

# Private functions
my $bind_option = sub {
   my ($v, $opts) = @_;

   my $prefix = $opts->{prefix} // NUL;
   my $numify = $opts->{numify} // FALSE;

   return is_arrayref $v
        ? { label =>  $v->[ 0 ].NUL,
            value => (defined $v->[ 1 ] ? ($numify ? 0 + ($v->[ 1 ] || 0)
                                                   : $prefix.$v->[ 1 ])
                                        : undef),
            %{ $v->[ 2 ] // {} } }
        : { label => "${v}", value => ($numify ? 0 + $v : $prefix.$v) };
};

my $_check_field = sub {
   my ($req, $class_base) = @_;

   my $params = $req->query_params;
   my $domain = $params->( 'domain' );
   my $class  = $params->( 'form'   );
   my $id     = $params->( 'id'     );
   my $val    = $params->( 'val', { raw => TRUE } );

   if    (first_char $class eq '+') { $class = substr $class, 1 }
   elsif (defined $class_base)      { $class = "${class_base}::${class}" }

   $result_class_cache->{ $class }
      or (ensure_class_loaded( $class )
          and $result_class_cache->{ $class } = TRUE);

   my $attr = $class->validation_attributes; $attr->{level} = 4;

   return Data::Validation->new( $attr )->check_field( $id, $val );
};

my $extension2format = sub {
   my ($map, $path) = @_; my $extn = (split m{ \. }mx, $path)[ -1 ] // NUL;

   return $map->{ $extn } // 'text';
};

my $get_tip_text = sub {
   my ($root, $node) = @_;

   my $path = $node->{path} or return NUL; my $text = $path->abs2rel( $root );

   $text =~ s{ \A [a-z]+ / }{}mx; $text =~ s{ \. .+ \z }{}mx;
   $text =~ s{ [/] }{ / }gmx;     $text =~ s{ [_] }{ }gmx;

   return $text;
};

my $sorted_keys = sub {
   my $node = shift;

   return [ sort { $node->{ $a }->{_order} <=> $node->{ $b }->{_order} }
            grep { first_char $_ ne '_' } keys %{ $node } ];
};

my $load_file_data = sub {
   my $node = shift; my $markdown = $node->{path}->all;

   my $yaml; $markdown =~ s{ \A --- $ ( .* ) ^ --- $ }{}msx and $yaml = $1;

   $yaml or return TRUE; my $data = $yaml_coder->read_string( $yaml )->[ 0 ];

   exists $data->{created} and $data->{created} = str2time $data->{created};

   $node->{ $_ } = $data->{ $_ } for (keys %{ $data });

   return TRUE;
};

my $make_tuple = sub {
   my $node = shift;

   ($node and exists $node->{type} and defined $node->{type})
      or return [ 0, [], $node ];

   my $keys = $node->{type} eq 'folder' ? $sorted_keys->( $node->{tree} ) : [];

   return [ 0, $keys, $node ];
};

my $nav_folder = sub {
   return { depth => $_[ 2 ] // 0,
            title => loc( $_[ 0 ], $_[ 1 ].'_management_heading' ),
            type  => 'folder', };
};

my $nav_linkto = sub {
   my ($req, $opts, $actionp, @args) = @_; my $name = $opts->{name};

   my $depth      = $opts->{depth} // 1;
   my $label_opts = { params => $opts->{label_args} // [],
                      no_quote_bind_values => TRUE, };

   return { depth => $depth,
            label => loc( $req, "${name}_link", $label_opts ),
            tip   => loc( $req, "${name}_tip"  ),
            type  => 'link',
            uri   => uri_for_action( $req, $actionp, @args ), };
};

my $_vehicle_link = sub {
   my ($req, $page, $args, $value, $action, $name) = @_;

   my $path = "asset/${action}"; my $params = { action => $action };

   $action eq 'unassign' and $params->{vehicle} = $value;

   my $href = uri_for_action( $req, $path, $args, $params );
   my $tip  = loc( $req, "${action}_management_tip" );
   my $js   = $page->{literal_js} //= [];

   push @{ $js }, dialog_anchor( "${action}_${name}", $href, {
      name    => "${action}-vehicle",
      title   => loc( $req, (ucfirst $action).' Vehicle' ),
      useIcon => \1 } );

   $value = (blessed $value) ? $value->slotref : $value;

   return table_link( $req, "${action}_${name}", $value, $tip );
};

# Public functions
sub admin_navigation_links ($) {
   my $req = shift; my $now = DateTime->now;

   return
      [ $nav_folder->( $req, 'events' ),
        $nav_linkto->( $req, { name => 'current_events' }, 'event/events', [],
                       after  => $now->clone->subtract( days => 1 )->ymd ),
        $nav_linkto->( $req, { name => 'previous_events' }, 'event/events', [],
                       before => $now->ymd ),
        $nav_folder->( $req, 'people' ),
        $nav_linkto->( $req, { name => 'contacts_list' }, 'admin/contacts', [],
                       status => 'current' ),
        $nav_linkto->( $req, { name => 'people_list' }, 'admin/people', [] ),
        $nav_linkto->( $req, { name => 'current_people_list' }, 'admin/people',
                       [], status => 'current' ),
        $nav_linkto->( $req, { name => 'bike_rider_list' }, 'admin/people', [],
                       role => 'bike_rider', status => 'current' ),
        $nav_linkto->( $req, { name => 'controller_list' }, 'admin/people', [],
                       role => 'controller', status => 'current' ),
        $nav_linkto->( $req, { name => 'driver_list' }, 'admin/people', [],
                       role => 'driver', status => 'current' ),
        $nav_linkto->( $req, { name => 'fund_raiser_list' }, 'admin/people', [],
                       role => 'fund_raiser', status => 'current' ),
        $nav_folder->( $req, 'types' ),
        $nav_linkto->( $req, { name => 'types_list' }, 'admin/types', [] ),
        $nav_folder->( $req, 'vehicles' ),
        $nav_linkto->( $req, { name => 'vehicles_list' },
                       'asset/vehicles', [] ),
        $nav_linkto->( $req, { name => 'bike_list' },
                       'asset/vehicles', [], type => 'bike' ),
        $nav_linkto->( $req, { name => 'service_bikes' },
                       'asset/vehicles', [], type => 'bike', service => TRUE ),
        $nav_linkto->( $req, { name => 'private_bikes' },
                       'asset/vehicles', [], type => 'bike', private => TRUE ),
        ];
}

sub assign_link ($$$$) { # Traffic lights
   my ($req, $page, $args, $opts) = @_;

   my $name = $opts->{name}; my $value = $opts->{vehicle};

   my $state = slot_claimed( $opts ) ? 'vehicle-not-needed' : NUL;

   $opts->{vehicle_req} and $state = 'vehicle-requested';
   $value and $state = 'vehicle-assigned';

   if ($state eq 'vehicle-assigned') {
      $value
         = $_vehicle_link->( $req, $page, $args, $value, 'unassign', $name );
   }
   elsif ($state eq 'vehicle-requested') {
      $value
         = $_vehicle_link->( $req, $page, $args, 'requested', 'assign', $name );
   }

   my $class = "centre narrow ${state}";

   return { value => $value, class => $class };
}

sub bind ($;$$) {
   my ($name, $v, $opts) = @_; $opts = { %{ $opts // {} } };

   my $numify = $opts->{numify} // FALSE;
   my $params = { label => $name, name => $name }; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $params->{value} = $v->dmy( '/' );
   }
   elsif (is_arrayref $v) {
      $params->{value} = [ map { $bind_option->( $_, $opts ) } @{ $v } ];
   }
   else { defined $v and $params->{value} = $numify ? 0 + $v : "${v}" }

   delete $opts->{numify}; delete $opts->{prefix};

   $params->{ $_ } = $opts->{ $_ } for (keys %{ $opts });

   return $params;
}

sub bind_fields ($$$$) {
   my ($schema, $src, $map, $result) = @_; my $fields = {};

   for my $k (keys %{ $map }) {
      my $value = exists $map->{ $k }->{checked} ? TRUE : $src->$k();
      my $opts  = field_options( $schema, $result, $k, $map->{ $k } );

      $fields->{ $k } = &bind( $k, $value, $opts );
   }

   return $fields;
}

sub bool_data_type (;$) {
   return { data_type     => 'boolean',
            default_value => $_[ 0 ] // FALSE,
            is_nullable   => FALSE, };
}

sub build_navigation ($$) {
   my ($req, $opts) = @_; my @nav = ();

   my $ids = $req->uri_params->() // []; my $iter = iterator( $opts->{node} );

   while (defined (my $node = $iter->())) {
      $node->{id} eq 'index' and next;

      my $link   = clone( $node ); delete $link->{tree};
      my $prefix = $link->{prefix};

      $link->{class}  = $node->{type} eq 'folder' ? 'folder-link' : 'file-link';
      $link->{tip  }  = $get_tip_text->( $opts->{config}->docs_root, $node );
      $link->{label}  = $opts->{label}->( $link );
      $link->{uri  }  = uri_for_action( $req, $opts->{path}, [ $link->{url} ] );
      $link->{depth} -= 2;

      if (defined $ids->[ 0 ] and $ids->[ 0 ] eq $node->{id}) {
         $link->{class} .= $node->{url} eq $opts->{wanted}
                         ? ' active' : ' open';
         shift @{ $ids };
      }

      push @nav, $link;
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

sub button ($$;$$$) {
   my ($req, $opts, $action, $name, $args) = @_; my $class = $opts->{class};

   my $conk   = $action && $name ? 'container_class' : 'class';
   my $label  = $opts->{label} // "${action}_${name}";
   my $value  = $opts->{value} // "${action}_${name}";
   my $button = { $conk => $class, label => $label, value => $value };

   $action and $name
      and $button->{tip} = make_tip( $req, "${action}_${name}_tip", $args );

   return $button;
}

sub check_field_server ($$) {
   my ($k, $opts) = @_;

   my $args = $json_coder->encode( [ $k, $opts->{form}, $opts->{domain} ] );

   return "   behaviour.config.server[ '${k}' ] = {",
          "      method    : 'checkField',",
          "      event     : 'blur',",
          "      args      : ${args} };";
}

sub check_form_field ($;$$) {
   my ($req, $log, $result_class_base) = @_; my $mesg;

   my $id = $req->query_params->( 'id' ); my $meta = { id => "${id}_ajax" };

   try   { $_check_field->( $req, $result_class_base ) }
   catch {
      my $e = $_; my $args = { params => $e->args };

      $log and $log->debug( "${e}" );
      $mesg = $req->loc( $e->error, $args );
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

sub create_link ($$$;$) {
   my ($req, $actionp, $k, $opts) = @_; $opts //= {};

   return { container_class => $opts->{container_class} // NUL,
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $actionp, $opts->{args} // [] ),
            name  => "create_${k}",
            tip   => loc( $req, "${k}_create_tip", [ $k ] ),
            type  => 'link',
            value => loc( $req, "${k}_create_link" ) };
}

sub date_data_type () {
   return { data_type     => 'datetime',
            default_value => '0000-00-00',
            is_nullable   => TRUE,
            datetime_undef_if_invalid => TRUE, }
}

sub delete_button ($$;$) {
   my ($req, $name, $type) = @_;

   my $button = { container_class => 'right', label => 'delete',
                  value           => "delete_${type}" };

   $type and $button->{tip} = make_tip( $req, 'delete_tip', [ $type, $name ] );

   return $button;
}

sub dialog_anchor ($$$) {
   my ($k, $href, $opts) = @_;

   my $args = $json_coder->encode( [ "${href}", $opts ] );

   return "   behaviour.config.anchors[ '${k}' ] = {",
          "      method    : 'modalDialog',",
          "      args      : ${args} };";
}

sub enumerated_data_type ($;$) {
   return { data_type     => 'enum',
            default_value => $_[ 1 ],
            extra         => { list => $_[ 0 ] },
            is_enum       => TRUE, };
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

sub field_options ($$$;$) {
   my ($schema, $result, $name, $opts) = @_; my $mandy; $opts //= {};

   unless (defined ($mandy = $field_option_cache->{ $result }->{ $name })) {
      my $class       = blessed $schema->resultset( $result )->new_result( {} );
      my $constraints = $class->validation_attributes->{fields}->{ $name };

      $mandy = $field_option_cache->{ $result }->{ $name }
             = exists $constraints->{validate}
                   && $constraints->{validate} =~ m{ isMandatory }mx
             ? ' required' : NUL;
   }

   $opts->{class} //= NUL; $opts->{class} .= $mandy;

   return $opts;
}

sub foreign_key_data_type (;$$) {
   my $type_info = { data_type     => 'integer',
                     default_value => $_[ 0 ],
                     extra         => { unsigned => TRUE },
                     is_nullable   => FALSE,
                     is_numeric    => TRUE, };

   defined $_[ 1 ] and $type_info->{accessor} = $_[ 1 ];

   return $type_info;
}

sub gcf {
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

sub lcm {
   return $_[ 0 ] * $_[ 1 ] / gcf( $_[ 0 ], $_[ 1 ] );
}

sub loc ($$;@) {
   my ($req, $k, @args) = @_;

   $translations->{ my $locale = $req->locale } //= {};

   return exists $translations->{ $locale }->{ $k }
               ? $translations->{ $locale }->{ $k }
               : $translations->{ $locale }->{ $k } = $req->loc( $k, @args );
}

sub localise_tree ($$) {
   my ($tree, $locale) = @_; ($tree and $locale) or return FALSE;

   exists $tree->{ $locale } and defined $tree->{ $locale }
      and return $tree->{ $locale };

   return FALSE;
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
   my ($req, $k, $args) = @_; $args //= [];

   return loc( $req, 'Hint' ).SPC.TILDE.SPC.loc( $req, $k, $args );
}

sub management_link ($$$;$) {
   my ($req, $actionp, $name, $opts) = @_; $opts //= {};

   my $args   = $opts->{args} // [ $name ];
   my ($moniker, $action) = split m{ / }mx, $actionp, 2;
   my $href   = uri_for_action( $req, $actionp, $args );
   my $type   = $opts->{type} // 'link';
   my $button = { class => 'table-link',
                  hint  => loc( $req, 'Hint' ),
                  href  => $href,
                  name  => "${name}-${action}",
                  tip   => loc( $req, "${action}_management_tip", @{ $args } ),
                  type  => $type,
                  value => loc( $req, "${action}_management_link" ), };

   if ($type eq 'form_button') {
      $button->{action   } = "${name}_${action}";
      $button->{form_name} = "${name}-${action}";
      $button->{tip      } = loc( $req, "${name}_${action}_tip", @{ $args } );
      $button->{value    } = loc( $req, "${name}_${action}_link" );
   }

   return $button;
}

sub mtime ($) {
   return $_[ 0 ]->{tree}->{_mtime};
}

sub new_salt ($$) {
   my ($type, $lf) = @_;

   return "\$${type}\$${lf}\$"
        . (en_base64( pack( 'H*', substr( create_token, 0, 32 ) ) ) );
}

sub nullable_foreign_key_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_nullable       => TRUE,
            is_numeric        => TRUE, };
}

sub nullable_varchar_data_type (;$$) {
   return { data_type         => 'varchar',
            default_value     => $_[ 1 ],
            is_nullable       => TRUE,
            size              => $_[ 0 ] || VARCHAR_MAX_SIZE, };
}

sub numerical_id_data_type (;$) {
   return { data_type         => 'smallint',
            default_value     => $_[ 0 ],
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub register_action_paths (;@) {
   my $args = (is_hashref $_[ 0 ]) ? $_[ 0 ] : { @_ };

   for my $k (keys %{ $args }) { $action_path_uri_map->{ $k } = $args->{ $k } }

   return;
}

sub rota_navigation_links ($$$) {
   my ($req, $period, $name) = @_; my $now = str2date_time time2str '%Y-%m-01';

   my $actionp = "sched/${period}_rota";
   my $nav     = [ $nav_folder->( $req, 'months' ) ];

   for my $mno (0 .. 11) {
      my $offset = $mno - 5;
      my $month  = $offset > 0 ? $now->clone->add( months => $offset )
                 : $offset < 0 ? $now->clone->subtract( months => -$offset )
                 :               $now->clone;
      my $opts   = { label_args => [ $month->year ],
                     name       => lc 'month_'.$month->month_abbr };
      my $args   = [ $name, $month->ymd ];

      push @{ $nav }, $nav_linkto->( $req, $opts, $actionp, $args );
   }

   return $nav;
}

sub save_button ($$;$) {
   my ($req, $name, $type) = @_; my $k = $name ? 'update' : 'create';

   my $button = { container_class => 'right-last', label => $k,
                  value           => "${k}_${type}" };

   $type and $button->{tip} = make_tip( $req, "${k}_tip", [ $type, $name ] );

   return $button;
}

sub serial_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_auto_increment => TRUE,
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub set_element_focus ($$) {
   my ($form, $name) = @_;

   return [ "var form = document.forms[ '${form}' ];",
            "var f = function() { behaviour.rebuild(); form.${name}.focus() };",
            'f.delay( 100 );', ];
}

sub set_on_create_datetime_data_type () {
   return { %{ date_data_type() }, set_on_create => TRUE };
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

sub slot_identifier ($$$$$) {
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

sub table_link ($$$$) {
   return { class => 'table-link windows', hint  => loc( $_[ 0 ], 'Hint' ),
            href  => HASH_CHAR,            name  => $_[ 1 ],
            tip   => $_[ 3 ],              type  => 'link',
            value => $_[ 2 ], };
}

sub uri_for_action ($$;@) {
   my ($req, $action, @args) = @_;

   blessed $req or throw 'Not a request object [_1]', [ $req ];

   my $uri = $action_path_uri_map->{ $action } // $action;

   return $req->uri_for( $uri, @args );
}

sub varchar_data_type (;$$) {
   return { data_type         => 'varchar',
            default_value     => $_[ 1 ] // NUL,
            is_nullable       => FALSE,
            size              => $_[ 0 ] || VARCHAR_MAX_SIZE, };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Util - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Util;
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
