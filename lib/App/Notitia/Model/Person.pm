package App::Notitia::Model::Person;

use Algorithm::Combinatorics qw( combinations );
use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants  qw( C_DIALOG EXCEPTION_CLASS FALSE
                                 NUL PIPE_SEP SPC TRUE );
use App::Notitia::DOM        qw( new_container p_action p_button p_fields p_item
                                 p_js p_link p_list p_row p_select p_table
                                 p_textfield );
use App::Notitia::Util       qw( check_field_js dialog_anchor link_options locm
                                 make_tip management_link page_link_set
                                 register_action_paths to_dt to_msg );
use Class::Null;
use Class::Usul::Functions   qw( create_token is_member throw );
use Class::Usul::Types       qw( ArrayRef );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(App::Notitia::Role::Messaging);

# Public attributes
has '+moniker' => default => 'person';

register_action_paths
   'person/activate'       => 'person-activate',
   'person/contacts'       => 'contacts',
   'person/message'        => 'message-people',
   'person/mugshot'        => 'mugshot',
   'person/people'         => 'people',
   'person/person'         => 'person',
   'person/person_summary' => 'person-summary';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'management';
   $stash->{navigation}
      = $self->management_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_add_person_js = sub {
   my ($page, $name) = @_;

   my $opts = { domain => $name ? 'update' : 'insert', form => 'Person' };

   p_js $page,
      check_field_js( 'first_name',    $opts ),
      check_field_js( 'last_name',     $opts ),
      check_field_js( 'email_address', $opts ),
      check_field_js( 'postcode',      $opts );
};

my $_assert_not_self = sub {
   my ($person, $nok) = @_; $nok or undef $nok;

   $nok and $person->id and $nok == $person->id
        and throw 'Cannot set self as next of kin', level => 2;

   return $nok;
};

my $_bind_mugshot = sub {
   my ($conf, $req, $person) = @_;

   my $uri = $conf->assets.'/mugshot/'; my $href;

   if ($person->shortcode) {
      my $assets = $conf->assetdir->catdir( 'mugshot' );

      for my $extn (qw( .gif .jpeg .jpg .png )) {
         my $path = $assets->catfile( $person->shortcode.$extn );

         $path->exists
            and $href = $req->uri_for( $uri.$person->shortcode.$extn )
            and last;
      }
   }

   $href //= $req->uri_for( $uri.'nomugshot.png' );

   return { class => 'mugshot', href => $href,
            title => locm( $req, 'mugshot' ), type => 'image' };
};

my $_contact_links = sub {
   my ($req, $person) = @_; my @links; my $nok = $person->next_of_kin;

   push @links, { class => 'align-right', value => $person->home_phone };
   push @links, { class => 'align-right', value => $person->mobile_phone };
   push @links, { class => 'select-col align-center',
                  value => { name  => 'selected',
                             type  => 'checkbox',
                             value => $person->shortcode } };

   if (is_member 'person_manager', $req->session->roles) {
      push @links, { value => $nok ? $nok->label : NUL };
      push @links, { class => 'align-right',
                     value => $nok ? $nok->home_phone : NUL };
      push @links, { class => 'align-right',
                     value => $nok ? $nok->mobile_phone : NUL };
      push @links, { class => 'select-col align-center',
                     value => $nok ? { name  => 'selected',
                                       type  => 'checkbox',
                                       value => $nok->shortcode } : NUL };
   }

   return [ { value => $person->label }, @links ];
};

my $_header_link = sub {
   my ($req, $params, $actionp, $header, $col, $count) = @_;

   my $dirn = ($params->{orderby} // NUL) eq "desc.${col}" ? 'asc' : 'desc';
   my $href = $req->uri_for_action
      ( $actionp, [], { %{ $params }, orderby => "${dirn}.${col}" } );
   my $dirn_label = { asc => 'ascending', desc => 'descending' };

   return p_link {}, "${col}-header", $href, {
      request => $req,
      tip     => locm( $req, 'header_sort_tip', $col, $dirn_label->{ $dirn } ),
      value   => locm( $req, "${header}_${count}" ) };
};

my $_maybe_find_person = sub {
   return $_[ 1 ] ? $_[ 0 ]->find_by_shortcode( $_[ 1 ] ) : Class::Null->new;
};

my $_people_order = sub {
   my $params = shift;

   my ($dirn, $col) = split m{ \. }mx, $params->{orderby} // 'asc.name';

   return { "-${dirn}" => "me.${col}" };
};

my $_people_search_opts = sub {
   my ($req, $params) = @_;

   my $column  = $params->{filter_column } // 'none';
   my $pattern = $params->{filter_pattern} // NUL;

   ($column eq 'joined' or $column eq 'resigned') and $pattern = to_dt $pattern;

   return  {
      columns  => [ 'badge_id' ],
      filter_column  => $column,
      filter_pattern => $pattern,
      order_by => $_people_order->( $params ),
      page     => $params->{page} || 1,
      role     => $params->{role},
      rows     => $req->session->rows_per_page,
      status   => $params->{status},
      type     => $params->{type} // NUL, };
};

my $_people_title = sub {
   my ($req, $role, $status, $type) = @_;

   my $k = $role   ? "${role}_list_link"
         : $type   ? "${type}_list_heading"
         : $status ? "${status}_people_list_link"
         :           'people_management_heading';

   return locm $req, $k;
};

my $_select_nav_link_name = sub {
   my $opts = { %{ $_[ 0 ] } };

   return
        $opts->{type} && $opts->{type} eq 'contacts' ? 'contacts_list'
      : $opts->{role} && $opts->{role} eq 'committee' ? 'committee_list'
      : $opts->{role} && $opts->{role} eq 'controller' ? 'controller_list'
      : $opts->{role} && $opts->{role} eq 'driver' ? 'driver_list'
      : $opts->{role} && $opts->{role} eq 'fund_raiser' ? 'fund_raiser_list'
      : $opts->{role} && $opts->{role} eq 'rider' ? 'rider_list'
      : $opts->{role} && $opts->{role} eq 'staff' ? 'staff_list'
      : $opts->{role} && $opts->{role} eq 'trustee' ? 'trustee_list'
      : $opts->{status} && $opts->{status} eq 'current' ? 'current_people_list'
      : $opts->{status} && $opts->{status} eq 'inactive'
         ? 'inactive_people_list'
      : $opts->{status} && $opts->{status} eq 'resigned'
         ? 'resigned_people_list'
      : 'people_list';
};

# Private methods
my $_bind_next_of_kin = sub {
   my ($self, $person, $disabled) = @_;

   my $opts   = { fields => { selected => $person->next_of_kin } };
   my $people = $self->schema->resultset( 'Person' )->list_all_people( $opts );

   $opts = { numify => TRUE, type => 'select',
             value  => [ [ NUL, NUL ], @{ $people } ] };
   $disabled and $opts->{disabled} = TRUE;

   return $opts;
};

my $_bind_region = sub {
   my ($self, $person, $disabled) = @_;

   my %sr    = %{ $self->config->slot_region };
   my @keys  = map { uc substr $sr{ $_ }, 0, 1 } sort keys %sr;
   my $value = [ map {
      [ $_, $_, { selected => $_ eq $person->region ? TRUE : FALSE } ] }
                 map { map { join NUL, @{ $_ } }
                       combinations( [ @keys ], $_ ) } 1 .. scalar @keys ];

   return {
      class    => 'single-character',
      disabled => $disabled,
      type     => 'select',
      value    => $value };
};

my $_bind_view_nok = sub {
   my ($self, $req, $person, $disabled) = @_;

   $person->next_of_kin or return { value => NUL };

   my $actionp = $self->moniker.($disabled ? '/person_summary' : '/person');
   my $nok = $person->next_of_kin;

   return ;
};

my $_filter_controls = sub {
   my ($self, $req, $params) = @_;

   my $f_col = $params->{filter_column} // 'none';
   my $href = $req->uri_for_action( $self->moniker.'/people' );
   my $form = new_container 'filter-controls', $href, { class => 'link-group' };
   my $opts = { class => 'single-character filter-column',
                label_field_class => 'control-label' };
   my @columns = qw( badge_id email_address joined name
                     postcode resigned shortcode );

   p_select $form, 'filter_column',
      [ map { [ $_, $_, { selected => $_ eq $f_col ? TRUE : FALSE } ] }
        'none', @columns ], $opts;

   p_textfield $form, 'filter_pattern', $params->{filter_pattern}, {
      class => 'single-character filter-pattern',
      label_field_class => 'control-label' };

   p_button $form, 'filter_list', 'filter_list', {
      class => 'button', tip => make_tip $req, 'filter_list_tip' };

   $self->add_csrf_token( $req, $form );

   return [ $form ];
};

my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search_for_role_types->all ];
};

my $_next_badge_id = sub {
   return $_[ 0 ]->schema->resultset( 'Person' )->next_badge_id( $_[ 1 ] );
};

my $_people_headers = sub {
   my ($self, $req, $params) = @_; my ($header, $max);

   my $role = $params->{role} // NUL; my $type = $params->{type} // NUL;

   if ($type eq 'contacts') {
      $header = 'contacts_heading';
      $max = is_member( 'person_manager', $req->session->roles) ? 7 : 3;

      return [ map { { value => locm( $req, "${header}_${_}" ) } } 0 .. $max ];
   }

   $header = 'people_role_heading';

   if ($role eq 'driver' or $role eq 'rider') { $max = 5 }
   elsif ($role eq 'controller' or $role eq 'fund_raiser') { $max = 4 }
   elsif ($role) { $max = 2 }
   else { $header = 'people_heading'; $max = 4 }

   my $actionp = $self->moniker.'/people';

   return [ {
      value => $_header_link->
         ( $req, $params, $actionp, $header, 'badge_id', 0 ) }, {
      value => $_header_link->
         ( $req, $params, $actionp, $header, 'name', 1 ) }, map { {
      value => locm( $req, "${header}_${_}" ) } } 2 .. $max
   ];
};

my $_people_links = sub {
   my ($self, $req, $params, $person) = @_; my $links = [];

   $params->{type} and $params->{type} eq 'contacts'
                   and return $_contact_links->( $req, $person );

   my $scode   =  $person->shortcode;
   my $action  =  is_member( 'person_manager', $req->session->roles )
               ?  'person' : 'person_summary';
   my $actionp =  $self->moniker."/${action}";
   my $href    =  $req->uri_for_action( $actionp, [ $scode ], $params );

   p_item $links, $person->badge_id, { class => 'align-right narrow' };

   p_item $links, p_link {}, "${scode}-${action}", $href, {
      request  => $req,
      tip      => locm( $req, "${action}_management_tip", $person->label ),
      value    => $person->label };

   my @paths = (); push @paths, 'role/role';
   my $role  = $params->{role};

   $role or  push @paths, 'user/email_subs', 'user/sms_subs';

   $role and is_member $role, qw( controller driver fund_raiser rider )
         and push @paths, 'train/training', 'certs/certifications';

   $role and ($role eq 'driver' or $role eq 'rider')
         and push @paths, 'blots/endorsements';

   for my $actionp ( @paths ) {
      push @{ $links }, { value => management_link $req, $actionp, $scode, {
         params => $params } };
   }

   return $links;
};

my $_people_ops_links = sub {
   my ($self, $req, $params, $page, $pager) = @_; my $links = [];

   my $moniker = $self->moniker; my $actionp = "${moniker}/people";

   my $page_links = page_link_set $req, $actionp, [], $params, $pager;

   $page_links and push @{ $links }, $page_links;

   my $href = $req->uri_for_action( "${moniker}/message", [], $params );

   $self->message_link( $req, $page, $href, 'message_people', $links );

   p_link $links, 'person', $req->uri_for_action( "${moniker}/person" ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_person_ops_links = sub {
   my ($self, $req, $page, $person) = @_;

   my $links = []; $person->id or return $links;

   my $moniker = $self->moniker; my $scode = $person->shortcode;

   for my $actionp (qw( certs/certifications blots/endorsements
                        train/training )) {
      push @{ $links }, management_link $req, $actionp, $scode;
   }

   my $href = $req->uri_for_action( "${moniker}/mugshot", [ $scode ] );

   p_js $page, dialog_anchor 'upload_mugshot', $href, {
      name => 'mugshot_upload', title => locm( $req, 'Mugshot Upload' ), };

   p_link $links, 'mugshot', C_DIALOG, { action => 'upload', request => $req };

   my $actionp = "${moniker}/person"; my $view_nok;

   if (my $nok = $person->next_of_kin) {
      p_link $links, 'nok', $req->uri_for_action( $actionp, [ $nok ] ), {
         action => 'view', container_class => 'add-link', request => $req };
   }

   p_link $links, 'person', $req->uri_for_action( $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_update_person_from_request = sub {
   my ($self, $req, $schema, $person) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( active address badge_expires badge_id dob email_address
                     first_name home_phone joined last_name location
                     coordinates mobile_phone name notes password_expired
                     postcode region resigned subscription )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts );

      not defined $v and is_member $attr, [ qw( active password_expired ) ]
          and $v = FALSE;

      $attr eq 'badge_id' and defined $v and not length $v and undef $v;

      defined $v or next; $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      length $v and is_member $attr,
         [ qw( badge_expires dob joined resigned subscription ) ]
         and $v = to_dt $v;

      $person->$attr( $v );
   }

   $person->set_totp_secret( $params->( 'enable_2fa', $opts ) ? TRUE : FALSE );
   $person->resigned and $person->active( FALSE );
   $person->next_of_kin_id
      ( $_assert_not_self->( $person, $params->( 'next_of_kin', $opts ) ) );
   $person->badge_id and $person->badge_id eq 'next'
      and $person->badge_id( $self->$_next_badge_id( $req ) );
   return;
};

my $_bind_person_fields = sub {
   my ($self, $req, $form, $person, $opts) = @_; $opts //= {};

   my $disabled  = $opts->{disabled} // FALSE;
   my $is_create = $opts->{action} && $opts->{action} eq 'create'
                 ? TRUE : FALSE;

   return
   [  mugshot          => $_bind_mugshot->( $self->config, $req, $person ),
      first_name       => { class    => 'narrow-field server',
                            disabled => $disabled },
      last_name        => { class    => 'narrow-field server',
                            disabled => $disabled },
      primary_role     => { class    => 'narrow-field',
                            disabled => $disabled,
                            type     => 'select',
                            value    => $person->shortcode
                                     ? $person->list_roles
                                     : $self->$_list_all_roles() },
      email_address    => { class    => 'standard-field server',
                            disabled => $disabled },
      address          => { disabled => $disabled },
      location         => { disabled => $disabled },
      postcode         => { class    => 'standard-field server',
                            disabled => $disabled },
      coordinates      => { disabled => $disabled },
      mobile_phone     => { disabled => $disabled },
      home_phone       => { disabled => $disabled },
      next_of_kin      => $self->$_bind_next_of_kin( $person, $disabled ),
      dob              => { disabled => $disabled, type => 'date' },
      joined           => { disabled => $disabled, type => 'date' },
      resigned         => { class    => 'standard-field clearable',
                            disabled => $disabled, type => 'date' },
      subscription     => { disabled => $disabled, type => 'date' },
      badge_id         => { disabled => $person->badge_id ? TRUE : $disabled,
                            tip      => make_tip( $req, 'badge_id_field_tip'),
                            value    => $is_create ? 'next' : undef },
      badge_expires    => { disabled => $disabled, type => 'date' },
      notes            => $disabled ? FALSE : {
         class         => 'standard-field autosize', type => 'textarea' },
      name             => { class    => 'standard-field',
                            disabled => $disabled, label => 'username',
                            tip => make_tip( $req, 'username_field_tip' ) },
      region           => $self->$_bind_region( $person, $disabled ),
      enable_2fa       => $is_create || $disabled ? FALSE : {
         checked       => $person->totp_secret ? TRUE : FALSE,
         label_class   => 'right', type => 'checkbox' },
      active           => $is_create || $disabled ? FALSE : {
         checked       => $person->active,
         label_class   => 'left', type => 'checkbox' },
      password_expired => $is_create || $disabled ? FALSE : {
         checked       => $person->password_expired,
         label_class   => 'right', type => 'checkbox' },
      ];
};

# Public methods
sub activate : Role(anon) {
   my ($self, $req) = @_; my ($location, $message);

   my $file = $req->uri_params->( 0 );
   my $path = $self->config->sessdir->catfile( $file );

   if ($path->exists and $path->is_file) {
      my $name   = $path->chomp->getline; $path->unlink;
      my $person = $self->find_by_shortcode( $name ); $person->activate;
      my $places = $self->config->places;

      $req->session->username( $name );
      $self->send_event( $req, "action:activate-person shortcode:${name}" );
      $location = $req->uri_for_action( $places->{password}, [ $name ] );
      $message  = [ to_msg '[_1] account activated', $person->label ];
   }
   else {
      $location = $req->base;
      $message  = [ 'Key [_1] unknown activation attempt', $file ];
   }

   return { redirect => { location => $location, message => $message } };
}

sub contacts : Role(address_viewer) Role(person_manager) Role(controller) {
   my ($self, $req) = @_; return $self->people( $req, 'contacts' );
}

sub create_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $person = $self->schema->resultset( 'Person' )->new_result( {} );

   $self->$_update_person_from_request( $req, $self->schema, $person );

   my $role = $req->body_params->( 'primary_role', { optional => TRUE } );

   $person->password( my $password = substr create_token, 0, 12 );
   $person->password_expired( TRUE );

   my $name = $person->name || 'with no name';
   my $create = sub {
      $person->insert; $role and $person->add_member_to( $role );
      $self->create_coordinate_lookup_job( {}, $person );
   };

   try   { $self->schema->txn_do( $create ) }
   catch { $self->blow_smoke( $_, 'create', 'person', $name ) };

   my $job; my $job_label = NUL;

   $person->can_email
      and $job = $self->create_person_email( $req, $person, $password )
      and $job_label = $job->label;

   my $message  = 'action:create-person shortcode:'.$person->shortcode;

   $self->send_event( $req, $message );

   my $who      = $req->session->user_label;
   my $key      = '[_1] created by [_2] ref. [_3]';
   my $params   = $req->query_params->( { optional => TRUE } );
   my $location = $req->uri_for_action( $self->moniker.'/people', [], $params );

   $message = [ to_msg $key, $person->label, $who, $job_label ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->find_by_shortcode( $name );
   my $label    = $person->label;

   $name eq 'admin' and throw 'Cannot delete the admin user';

   try   { $self->schema->txn_do( sub { $person->delete } ) }
   catch { $self->blow_smoke( $_, 'delete', 'person', $name ) };

   $self->send_event( $req, "action:delete-person shortcode:${name}" );

   my $who      = $req->session->user_label;
   my $params   = $req->query_params->( { optional => TRUE } );
   my $location = $req->uri_for_action( $self->moniker.'/people', [], $params );
   my $message  = [ to_msg '[_1] deleted by [_2]', $label, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub filter_list_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $actionp  = $self->moniker.'/people';
   my $column   = $req->body_params->( 'filter_column' );
   my $pattern  = $req->body_params->( 'filter_pattern', { raw => TRUE } );
   my $params   = { %{ $req->query_params->() },
                    filter_column => $column, filter_pattern => $pattern, };
   my $location = $req->uri_for_action( $actionp, [], $params );

   return { redirect => { location => $location } };
}

sub find_by_shortcode {
   return shift->schema->resultset( 'Person' )->find_by_shortcode( @_ );
}

sub message : Dialog Role(person_manager) {
   return $_[ 0 ]->message_stash( $_[ 1 ] );
}

sub message_create_action : Role(person_manager) {
   return $_[ 0 ]->message_create( $_[ 1 ], { action => 'people' } );
}

sub mugshot : Dialog Role(person_manager) {
   my ($self, $req) = @_;

   my $scode  = $req->uri_params->( 0 );
   my $stash  = $self->dialog_stash( $req );
   my $places = $self->config->places;
   my $params = { name => $scode, type => 'mugshot' };
   my $href   = $req->uri_for_action( $places->{upload}, [], $params );

   $stash->{page}->{forms}->[ 0 ] = new_container 'upload-file', $href;
   $self->components->{docs}->upload_dialog( $req, $stash->{page} );

   return $stash;
}

sub person : Role(person_manager) {
   my ($self, $req) = @_; my $people;

   my $name       =  $req->uri_params->( 0, { optional => TRUE } );
   my $role       =  $req->query_params->( 'role', { optional => TRUE } );
   my $status     =  $req->query_params->( 'status', { optional => TRUE } );
   my $page_no    =  $req->query_params->( 'page', { optional => TRUE } );
   my $actionp    =  $self->moniker.'/person';
   my $params     =  { page => $page_no };
   my $href       =  $req->uri_for_action( $actionp, [ $name ], $params );
   my $form       =  new_container 'person-admin', $href;
   my $action     =  $name ? 'update' : 'create';
   my $page       =  {
      first_field => 'first_name',
      forms       => [ $form ],
      selected    => $role ? "${role}_list"
                   : $status && $status eq 'current' ? 'current_people_list'
                   : 'people_list',
      title       => locm $req,  "person_${action}_heading" };
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $opts       =  { action => $action };
   my $fields     =  $self->$_bind_person_fields( $req, $form, $person, $opts );
   my $links      =  $self->$_person_ops_links( $req, $page, $person );
   my $args       =  [ 'person', $person->label ];

   p_list $form, PIPE_SEP, $links, link_options 'right';

   p_fields $form, $self->schema, 'Person', $person, $fields;

   p_action $form, $action, $args, { request => $req };

   $name and p_action $form, 'delete', $args, { request => $req };

   $_add_person_js->( $page, $name ),

   return $self->get_stash( $req, $page );
}

sub person_summary : Role(person_manager) Role(address_viewer)
                     Role(training_manager) {
   my ($self, $req) = @_; my $people;

   my $name       =  $req->uri_params->( 0 );
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $form       =  new_container { class => 'standard-form' };
   my $opts       =  { disabled => TRUE };
   my $fields     =  $self->$_bind_person_fields( $req, $form, $person, $opts );
   my $page       =  {
      first_field => 'first_name',
      forms       => [ $form ],
      title       => locm $req, 'person_summary_heading', };

   p_fields $form, $self->schema, 'Person', $person, $fields;

   return $self->get_stash( $req, $page );
}

sub people : Role(administrator) Role(person_manager) Role(address_viewer) {
   my ($self, $req, $type) = @_;

   my $params  =  $req->query_params->( { optional => TRUE } );

   delete $params->{mid};
   $type and $params->{type} = $type; $type = $params->{type} || NUL;

   my $role    =  $params->{role  };
   my $status  =  $params->{status};
   my $s_opts  =  $_people_search_opts->( $req, $params );
   my $actionp =  $self->moniker.'/people';
   my $href    =  $req->uri_for_action( $actionp, [], $params );
   my $form    =  new_container 'people', $href, {
      class    => 'wider-table', id => 'people' };
   my $page    =  {
      forms    => [ $form ],
      selected => $_select_nav_link_name->( $s_opts ),
      title    => $_people_title->( $req, $role, $status, $type ), };
   my $rs      =  $self->schema->resultset( 'Person' );
   my $people  =  $rs->search_for_people( $s_opts );
   my $links   =  $self->$_people_ops_links
      ( $req, $params, $page, $people->pager );

   p_list $form, PIPE_SEP, $links, link_options 'right';

   my $table   = p_table $form, {
      headers => $self->$_people_headers( $req, $params ) };

   $type eq 'contacts' and is_member( 'person_manager', $req->session->roles )
      and $table->{class} = 'smaller-table';

   p_row $table, [ map { $self->$_people_links( $req, $params, $_ ) }
                   $people->all ];

   p_list $form, NUL, $self->$_filter_controls( $req, $s_opts ), link_options;

   return $self->get_stash( $req, $page );
}

sub update_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $scode  = $req->uri_params->( 0 );
   my $person = $self->find_by_shortcode( $scode );
   my $pcode  = $person->postcode // NUL;
   my $label  = $person->label;

   $self->$_update_person_from_request( $req, $self->schema, $person );

   try {
      $person->update;
      $pcode ne $person->postcode
         and $self->create_coordinate_lookup_job( {}, $person );
   }
   catch { $self->blow_smoke( $_, 'update', 'person', $label ) };

   $self->send_event( $req, "action:update-person shortcode:${scode}" );

   my $who      = $req->session->user_label;
   my $params   = $req->query_params->( { optional => TRUE } );
   my $location = $req->uri_for_action( $self->moniker.'/people', [], $params );
   my $message  = [ to_msg '[_1] updated by [_2]', $label, $who ];

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Person - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Person;
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
