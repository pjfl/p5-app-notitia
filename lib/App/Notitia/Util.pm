package App::Notitia::Util;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Constants    qw( FALSE NUL SPC TILDE TRUE VARCHAR_MAX_SIZE );
use Class::Usul::Functions     qw( class2appdir create_token find_apphome
                                   first_char get_cfgfiles is_arrayref
                                   is_hashref is_member throw );
use Class::Usul::Time          qw( str2time time2str );
use Crypt::Eksblowfish::Bcrypt qw( en_base64 );
use Scalar::Util               qw( blessed weaken );
use YAML::Tiny;

our @EXPORT_OK = qw( admin_navigation_links bind bool_data_type
                     build_navigation build_tree clone create_button
                     date_data_type delete_button enumerated_data_type enhance
                     field_options foreign_key_data_type get_hashed_pw get_salt
                     is_draft is_encrypted iterator loc localise_tree
                     make_id_from make_name_from management_button mtime
                     new_salt nullable_foreign_key_data_type
                     nullable_varchar_data_type numerical_id_data_type
                     rota_navigation_links save_button serial_data_type
                     set_element_focus set_on_create_datetime_data_type
                     slot_identifier slot_limit_index register_action_paths
                     show_node stash_functions uri_for_action varchar_data_type
                     );

# Private class attributes
my $_action_path_uri_map = {}; # Key is an action path, value a partial URI
my $_field_option_cache = {};
my $_translations  = {};

# Private functions
my $bind_option = sub {
   my ($v, $opts) = @_;

   my $prefix = $opts->{prefix} // NUL;
   my $numify = $opts->{numify} // FALSE;

   return is_arrayref $v
        ? { label =>  $v->[ 0 ].NUL,
            value => ($v->[ 1 ] ? ($numify ? 0 + $v->[ 1 ] : $prefix.$v->[ 1 ])
                                : undef),
            %{ $v->[ 2 ] // {} } }
        : { label => "${v}", value => ($numify ? 0 + $v : $prefix.$v) };
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

my $transcoder = YAML::Tiny->new;

my $load_file_data = sub {
   my $node = shift; my $markdown = $node->{path}->all;

   my $yaml; $markdown =~ s{ \A --- $ ( .* ) ^ --- $ }{}msx and $yaml = $1;

   $yaml or return TRUE; my $data = $transcoder->read_string( $yaml )->[ 0 ];

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

my $l1_nav_link = sub {
   my ($req, $k, $action, @args) = @_;

   return { depth => 1,
            tip   => loc( $req, "${k}_tip"  ),
            title => loc( $req, "${k}_link" ),
            type  => 'link',
            url   => uri_for_action( $req, $action, @args ), };
};

# Public functions
sub admin_navigation_links ($) {
   my $req = shift;

   return [ $nav_folder->( $req, 'events' ),
            $l1_nav_link->( $req, 'events_list', 'event/events',   [] ),
            $nav_folder->( $req, 'people' ),
            $l1_nav_link->( $req, 'people_list', 'admin/people',   [] ),
            $l1_nav_link->( $req, 'bike_rider_list',
                            'admin/people', [], role => 'bike_rider' ),
            $l1_nav_link->( $req, 'controller_list',
                            'admin/people', [], role => 'controller' ),
            $l1_nav_link->( $req, 'driver_list',
                            'admin/people', [], role => 'driver' ),
            $l1_nav_link->( $req, 'fund_raiser_list',
                            'admin/people', [], role => 'fund_raiser' ),
            $nav_folder->( $req, 'vehicles' ),
            $l1_nav_link->( $req, 'vehicles_list', 'asset/vehicles', [] ), ];
}

sub bind ($;$$) {
   my ($name, $v, $opts) = @_; $opts = { %{ $opts // {} } };

   my $numify = $opts->{numify} // FALSE;
   my $params = { label => $name, name => $name }; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $params->{value} = $v->ymd;
   }
   elsif (is_arrayref $v) {
      $params->{value} = [ map { $bind_option->( $_, $opts ) } @{ $v } ];
   }
   else { defined $v and $params->{value} = $numify ? 0 + $v : "${v}" }

   delete $opts->{numify}; delete $opts->{prefix};

   $params->{ $_ } = $opts->{ $_ } for (keys %{ $opts });

   return $params;
}

sub bool_data_type (;$) {
   return { data_type     => 'boolean',
            default_value => $_[ 0 ] // FALSE,
            is_nullable   => FALSE, };
}

sub build_navigation ($$$$$$) {
   my ($req, $path, $conf, $tree, $ids, $wanted) = @_;

   my $iter = iterator( $tree ); my @nav = ();

   while (defined (my $node = $iter->())) {
      $node->{id} eq 'index' and next;

      my $link = clone( $node ); delete $link->{tree};

      $link->{class}  = $node->{type} eq 'folder' ? 'folder-link' : 'file-link';
      $link->{tip  }  = $get_tip_text->( $conf->docs_root, $node );
      $link->{url  }  = uri_for_action( $req, $path, [ $link->{url} ] );
      $link->{depth} -= 2;

      if (defined $ids->[ 0 ] and $ids->[ 0 ] eq $node->{id}) {
         $link->{class} .= $node->{url} eq $wanted ? ' active' : ' open';
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

sub clone (;$) {
   my $v = shift;

   is_arrayref $v and return [ @{ $v // [] } ];
   is_hashref  $v and return { %{ $v // {} } };
   return $v;
}

sub create_button ($$$) {
   my ($req, $action, $k) = @_;

   return { class => 'fade',
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $action ),
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

   $type and $button->{tip} = loc( $req, 'Hint' ).SPC.TILDE.SPC
                            . loc( $req, 'delete_tip', [ $type, $name ] );

   return $button;
};

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

   unless (defined ($mandy = $_field_option_cache->{ $result }->{ $name })) {
      my $class       = blessed $schema->resultset( $result )->new_result( {} );
      my $constraints = $class->validation_attributes->{fields}->{ $name };

      $mandy = $_field_option_cache->{ $result }->{ $name }
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

sub loc ($$;@) {
   my ($req, $k, @args) = @_;

   $_translations->{ my $locale = $req->locale } //= {};

   return exists $_translations->{ $locale }->{ $k }
               ? $_translations->{ $locale }->{ $k }
               : $_translations->{ $locale }->{ $k } = $req->loc( $k, @args );
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

sub management_button ($$$$) {
   my ($req, $name, $action, $href) = @_;

   return { class => 'table-link fade',
            hint  => loc( $req, 'Hint' ),
            href  => $href,
            name  => "${name}-${action}",
            tip   => loc( $req, "${action}_management_tip" ),
            type  => 'link',
            value => loc( $req, "${action}_management_link" ), };
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

   for my $k (keys %{ $args }) {
      $_action_path_uri_map->{ $k } = $args->{ $k };
   }

   return;
}

sub rota_navigation_links ($$) {
   my ($req, $name) = @_; my $args = []; my $year = time2str '%Y';

   for my $month (0 .. 11) {
      $args->[ $month ] = [ $name, sprintf '%s-%0.2d-01', $year, 1 + $month ];
   }

   return
      [ $nav_folder->( $req, 'months' ),
        $l1_nav_link->( $req, 'month_jan', 'sched/day_rota', $args->[  0 ] ),
        $l1_nav_link->( $req, 'month_feb', 'sched/day_rota', $args->[  1 ] ),
        $l1_nav_link->( $req, 'month_mar', 'sched/day_rota', $args->[  2 ] ),
        $l1_nav_link->( $req, 'month_apr', 'sched/day_rota', $args->[  3 ] ),
        $l1_nav_link->( $req, 'month_may', 'sched/day_rota', $args->[  4 ] ),
        $l1_nav_link->( $req, 'month_jun', 'sched/day_rota', $args->[  5 ] ),
        $l1_nav_link->( $req, 'month_jul', 'sched/day_rota', $args->[  6 ] ),
        $l1_nav_link->( $req, 'month_aug', 'sched/day_rota', $args->[  7 ] ),
        $l1_nav_link->( $req, 'month_sep', 'sched/day_rota', $args->[  8 ] ),
        $l1_nav_link->( $req, 'month_oct', 'sched/day_rota', $args->[  9 ] ),
        $l1_nav_link->( $req, 'month_nov', 'sched/day_rota', $args->[ 10 ] ),
        $l1_nav_link->( $req, 'month_dec', 'sched/day_rota', $args->[ 11 ] ) ];
}

sub save_button ($$;$) {
   my ($req, $name, $type) = @_; my $k = $name ? 'update' : 'create';

   my $button = { container_class => 'right', label => $k,
                  value           => "${k}_${type}" };

   $type and $button->{tip} = loc( $req, 'Hint' ).SPC.TILDE.SPC
                            . loc( $req, "${k}_tip", [ $type, $name ] );

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
   $dest->{loc           } = sub { loc( $req, $_[ 0 ] ) };
   $dest->{reference     } = sub { ref $_[ 0 ] };
   $dest->{show_node     } = \&show_node;
   $dest->{str2time      } = \&str2time;
   $dest->{time2str      } = \&time2str;
   $dest->{ucfirst       } = sub { ucfirst $_[ 0 ] };
   $dest->{uri_for       } = sub { $req->uri_for( @_ ), };
   $dest->{uri_for_action} = sub { uri_for_action( $req, @_ ), };
   return;
}

sub uri_for_action ($$;@) {
   my ($req, $action, @args) = @_;

   blessed $req or throw 'Not a request object [_1]', [ $req ];

   my $uri = $_action_path_uri_map->{ $action } // $action;

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
