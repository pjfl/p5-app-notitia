package App::Notitia::Role::Navigation;

use attributes ();
use namespace::autoclean;

use App::Notitia::Constants qw( FALSE HASH_CHAR NUL PIPE_SEP SPC TRUE );
use App::Notitia::DOM       qw( new_container p_button p_folder p_image p_item
                                p_js p_link p_list p_navlink p_text );
use App::Notitia::Util      qw( dialog_anchor local_dt locd locm
                                make_tip now_dt to_dt );
use Class::Usul::Functions  qw( is_member );
use Class::Usul::Time       qw( time2str );
use Moo::Role;

requires qw( add_csrf_token components );

# Private functions
my $_location_class = sub {
   my $location = $_[ 0 ]->{location} or return NUL;

   return $location eq $_[ 1 ] ? 'current' : NUL
};

my $_selected_class = sub {
   return $_[ 0 ]->{selected} eq $_[ 1 ] ? 'selected' : NUL
};

my $_list_roles_of = sub {
   my $attr = attributes::get( shift ) // {}; return $attr->{Role} // [];
};

my $_p_week_link = sub {
   my ($list, $req, $actionp, $rota_name, $date, $opts, $params) = @_;

   $opts = { %{ $opts } }; $params //= {}; $params->{rota_date} = $date->ymd;

   my $local_dt = delete $opts->{local_dt};
   my $name     = 'wk'.$date->week_number;
   my $value    = locm( $req, 'Week' ).SPC.$date->week_number;
   my $class    = $date->week_number eq $local_dt->week_number
                ? ($opts->{value} // NUL) ne 'spreadsheet' ? 'selected' : NUL
                : NUL;
   my $args     = [ $rota_name, $date->ymd ];

   p_navlink $list, $name, [ $actionp, $args, $params ], {
      class    => $class, request => $req,
      tip      => 'Navigate to week commencing [_1]',
      tip_args => [ locd $req, $date ], value => $value, %{ $opts }, };

   return;
};

my $_p_year_link = sub {
   my ($list, $req, $actionp, $rota_name, $date, $selected) = @_;

   my $tip    = 'Navigate to [_1]';
   my $args   = [ $rota_name, $date->ymd ];
   my $params = { rota_date => $date->ymd };

   p_navlink $list, $date->year, [ $actionp, $args, $params ], {
      class => $selected ? 'selected' : NUL, request => $req,
      tip   => $tip, tip_args => [ $date->year ],
      value => $date->year, };

   return;
};

# Private package variables
my $_method_roles_cache = {};

# Private methods
my $_method_roles = sub {
   my ($self, $actionp) = @_; my $map;

   $map = $_method_roles_cache->{ $actionp } and return $map;

   my ($moniker, $method) = split m{ / }mx, $actionp, 2;
   my $model = $self->components->{ $moniker };

   for my $role_name (@{ $_list_roles_of->( $model->can( $method ) ) }) {
      $map->{ $role_name } = TRUE;
   }

   return $_method_roles_cache->{ $actionp } = $map;
};

my $_allowed = sub {
   my ($self, $req, $actionp) = @_;

   my $roles = $self->$_method_roles( $actionp );

   $roles->{anon} and return TRUE;
   $req->authenticated or return FALSE;
   $roles->{any } and return TRUE;

   for my $role_name (@{ $req->session->roles }) {
      $roles->{ $role_name } and return TRUE;
   }

   return FALSE;
};

my $_admin_data_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   my @pages = qw( slot_roles types user_form user_table ); my $class = NUL;

   is_member $page->{selected}, map { "${_}_list" } @pages and $class = 'open';

   p_folder $list, 'data', {
         class => $class, depth => 1, request => $req,
         tip => 'Data Management Menu' };

   p_navlink $list, 'types_list', [ 'admin/types' ], {
      class => $_selected_class->( $page, 'types_list' ),
      depth => 2, request => $req };

   p_navlink $list, 'slot_roles_list', [ 'admin/slot_roles' ], {
      class => $_selected_class->( $page, 'slot_roles_list' ),
      depth => 2, request => $req };

   p_navlink $list, 'user_form_list', [ 'form/form_list' ], {
      class => $_selected_class->( $page, 'user_form_list' ),
      depth => 2, request => $req };

   p_navlink $list, 'user_table_list', [ 'table/table_list' ], {
      class => $_selected_class->( $page, 'user_table_list' ),
      depth => 2, request => $req };

   return;
};

my $_admin_log_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   my @logs  = qw( activity jobdaemon schema server util );

   my $class = NUL; is_member $page->{selected}, \@logs and $class = 'open';

   p_folder $list, 'logs', {
      class => $class, depth => 1, request => $req, tip => 'Logs Menu' };

   for my $log_name (@logs) {
      p_navlink $list, "${log_name}_log", [ 'log', [ $log_name ] ], {
         class => $_selected_class->( $page, $log_name ),
         depth => 2, request => $req };
   }

   return;
};

my $_admin_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   p_folder $list, 'admin', {
      request => $req, tip => "Administrator's Menu" };

   $self->$_admin_data_links( $req, $page, $nav );

   $self->$_admin_log_links( $req, $page, $nav );

   my $class = $page->{selected} eq 'jobdaemon_status'
            || $page->{selected} eq 'event_controls' ? 'open' : NUL;

   p_folder $list, 'process_control', {
      class => $class, depth => 1, request => $req,
      tip   => 'Process Control Menu' };

   p_navlink $list, 'jobdaemon_status', [ 'daemon/status' ], {
      class => $_selected_class->( $page, 'jobdaemon_status' ),
      depth => 2, request => $req };

   p_navlink $list, 'event_controls', [ 'admin/event_controls' ], {
      class => $_selected_class->( $page, 'event_controls' ),
      depth => 2, request => $req };

   return;
};

my $_authenticated_login_links = sub {
   my ($self, $req, $page, $nav) = @_;

   my $places = $self->config->places; my $list = $nav->{menu}->{list} //= [];

   p_navlink $list, 'profile', [ $places->{profile} ], {
      class   => $_selected_class->( $page, 'profile' ),
      request => $req, };

   p_navlink $list, 'change_password', [ $places->{password} ], {
      class   => $_selected_class->( $page, 'change_password' ),
      request => $req, };

   p_navlink $list, 'email_subscription', [ 'user/email_subs' ], {
      class   => $_selected_class->( $page, 'email_subscription' ),
      request => $req, };

   p_navlink $list, 'sms_subscription', [ 'user/sms_subs' ], {
      class   => $_selected_class->( $page, 'sms_subscription' ),
      request => $req, };

   $req->session->enable_2fa
      and p_navlink $list, 'totp_secret', [ 'user/totp_secret' ], {
         class   => $_selected_class->( $page, 'totp_secret' ),
         request => $req, };

   return;
};

my $_people_by_role_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   my @roles = qw( committee controller driver fund_raiser rider staff trustee);

   my $class = NUL; is_member $page->{selected}, map { "${_}_list" } @roles
      and $class = 'open';

   p_folder $list, 'people_by_type', {
      class   => $class, depth => 1,
      request => $req, tip => 'people_by_type_tip' };

   for my $role (@roles) {
      p_navlink $list, "${role}_list",
         [ 'person/people', [], role => $role, status => 'current' ], {
            class => $_selected_class->( $page, "${role}_list" ),
            depth => 2, request => $req, };
   }

   return;
};

my $_people_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   my $is_allowed_contacts = $self->$_allowed( $req, 'person/contacts' );
   my $is_allowed_people   = $self->$_allowed( $req, 'person/people' );

   ($is_allowed_contacts or $is_allowed_people) and
      p_folder $list, 'people', { request => $req, tip => 'People Menu' };

   if ($is_allowed_people) {
      p_navlink $list, 'people_list', [ 'person/people' ], {
         class   => $_selected_class->( $page, 'people_list' ),
         request => $req, };

      p_navlink $list, 'current_people_list',
         [ 'person/people', [], status => 'current' ], {
            class   => $_selected_class->( $page, 'current_people_list' ),
            request => $req, };
   }

   $is_allowed_contacts and p_navlink $list, 'contacts_list',
      [ 'person/contacts', [], status => 'current' ], {
         class   => $_selected_class->( $page, 'contacts_list' ),
         request => $req, };

   $is_allowed_people and $self->$_people_by_role_links( $req, $page, $nav );

   return;
};

my $_report_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   my $is_allowed_customers  = $self->$_allowed( $req, 'report/customers' );
   my $is_allowed_deliveries = $self->$_allowed( $req, 'report/deliveries' );
   my $is_allowed_incidents  = $self->$_allowed( $req, 'report/incidents' );
   my $is_allowed_people     = $self->$_allowed( $req, 'report/people' );
   my $is_allowed_slots      = $self->$_allowed( $req, 'report/slots' );

   $is_allowed_customers or $is_allowed_deliveries or $is_allowed_incidents
      or $is_allowed_people or $is_allowed_slots or return;

   p_folder $list, 'reports', { request => $req, tip => 'Report Menu' };

   $is_allowed_customers and p_navlink $list, 'customer_report',
      [ 'report/customers', [], period => 'year-to-date' ], {
         class   => $_selected_class->( $page, 'customer_report' ),
         request => $req };

   $is_allowed_deliveries and p_navlink $list, 'delivery_report',
      [ 'report/deliveries', [], period => 'year-to-date' ], {
         class   => $_selected_class->( $page, 'delivery_report' ),
         request => $req };

   $is_allowed_incidents and p_navlink $list, 'incident_report',
      [ 'report/incidents', [], period => 'year-to-date' ], {
         class   => $_selected_class->( $page, 'incident_report' ),
         request => $req };

   $is_allowed_people and p_navlink $list, 'people_report',
      [ 'report/people', [], period => 'year-to-date' ], {
         class   => $_selected_class->( $page, 'people_report' ),
         request => $req };

   $is_allowed_people and p_navlink $list, 'people_meta_report',
      [ 'report/people_meta', [], period => 'year-to-date' ], {
         class   => $_selected_class->( $page, 'people_meta_report' ),
         request => $req };

   $is_allowed_slots and p_navlink $list, 'slot_report',
      [ 'report/slots', [], period => 'year-to-date' ], {
         class   => $_selected_class->( $page, 'slot_report' ),
         request => $req };

   $is_allowed_slots and p_navlink $list, 'vehicle_report',
      [ 'report/vehicles', [], period => 'year-to-date' ], {
         class   => $_selected_class->( $page, 'vehicle_report' ),
         request => $req };

   return;
};

my $_rota_month_links = sub {
   my ($self, $req, $actionp, $rota_name, $f_dom, $local_dt, $nav) = @_;

   my $list = $nav->{menu}->{list} //= [];

   p_folder $list, 'months', { request => $req };

   for my $mno (0 .. 11) {
      my $offset = $mno - 5;
      my $date   = $offset > 0 ? $f_dom->clone->add( months => $offset )
                 : $offset < 0 ? $f_dom->clone->subtract( months => -$offset )
                 :               $f_dom->clone;
      my $last_week = $date->clone->add( months => 1 )->subtract( days => 1 );
      my $name   = lc 'month_'.$date->month_abbr;
      my $args   = [ $rota_name, $date->ymd ];

      p_navlink $list, $name, [ $actionp, $args ], {
         class      => $date->month == $local_dt->month ? 'selected' : NUL,
         request    => $req,
         tip_args   => [ $date->month_name, $date->week_number,
                         $last_week->week_number ],
         value_args => [ $date->year ], };
   }

   return;
};

my $_rota_week_links = sub {
   my ($self, $req, $name, $sow, $local_dt, $nav) = @_;

   my $list = $nav->{menu}->{list};

   p_folder $list, 'week', { request => $req };

   my $actionp = 'week/week_rota'; my $opts = { local_dt => $local_dt };

   $_p_week_link->( $list, $req, $actionp, $name,
                    $sow->clone->subtract( weeks => 1 ), $opts );
   $_p_week_link->( $list, $req, $actionp, $name, $sow, $opts );
   $_p_week_link->( $list, $req, $actionp, $name,
                    $sow->clone->add( weeks => 1 ), $opts );
   $_p_week_link->( $list, $req, $actionp, $name,
                    $sow->clone->add( weeks => 2 ), $opts );
   $_p_week_link->( $list, $req, $actionp, $name,
                    $sow->clone->add( weeks => 3 ), $opts );
   $_p_week_link->( $list, $req, $actionp, $name,
                    $sow->clone->add( weeks => 4 ), $opts );
   return;
};

my $_secondary_authenticated_links = sub {
   my ($self, $req, $page, $nav) = @_;

   my $places = $self->config->places;

   p_navlink $nav, 'rota', [ $places->{rota} ], {
      class => $_location_class->( $page, 'schedule' ), request => $req,
      tip   => 'rota_link_tip', };

   my $after = now_dt->subtract( days => 1 )->ymd;
   my $index = $places->{admin_index};

   p_navlink $nav, 'admin_index', [ $index, [], after => $after ], {
      class => $_location_class->( $page, 'admin' ), request => $req, };

   $self->$_allowed( $req, 'call/journeys' )
      and p_navlink $nav, 'calls', [ 'call/journeys' ], {
         class => $_location_class->( $page, 'calls' ), request => $req, };

   return;
};

my $_unauthenticated_login_links = sub {
   my ($self, $req, $page, $nav) = @_;

   my $places = $self->config->places; my $list = $nav->{menu}->{list} //= [];

   p_navlink $list, 'login', [ $places->{login} ], {
      class => $_selected_class->( $page, 'login' ), request => $req, };

   p_navlink $list, 'change_password', [ $places->{password} ], {
      class => $_selected_class->( $page, 'change_password' ),
      request => $req, };

   p_navlink $nav->{menu}, 'request_reset', '#', {
      class => 'windows', request => $req, };

   $list->[ -1 ]->{depth} = 1; $list->[ -1 ]->{type} = 'link'; # Ugh

   my $href = $req->uri_for_action( 'user/reset' );

   p_js $page, dialog_anchor 'request_reset', $href, {
      title => locm $req, 'request_reset_title', };

   p_navlink $nav->{menu}, 'totp_request', '#', {
      class => 'windows', request => $req, };

   $list->[ -1 ]->{depth} = 1; $list->[ -1 ]->{type} = 'link'; # More ugh

   $href = $req->uri_for_action( 'user/totp_request' );

   p_js $page, dialog_anchor 'totp_request', $href, {
      title => locm $req, 'totp_request_title', };

   return;
};

my $_vehicle_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   p_folder $list, 'vehicles', { request => $req, tip => 'Vehicle Menu' };

   p_navlink $list, 'vehicles_list', [ 'asset/vehicles' ], {
      class => $_selected_class->( $page, 'vehicles_list' ), request => $req };

   p_navlink $list, 'adhoc_vehicles',
      [ 'asset/vehicles', [], adhoc => TRUE ], {
         class   => $_selected_class->( $page, 'adhoc_vehicles' ),
         request => $req };

   p_navlink $list, 'service_vehicles',
      [ 'asset/vehicles', [], service => TRUE ], {
         class   => $_selected_class->( $page, 'service_vehicles' ),
         request => $req };

   p_navlink $list, 'private_vehicles',
      [ 'asset/vehicles', [], private => TRUE ], {
         class   => $_selected_class->( $page, 'private_vehicles' ),
         request => $req };

   return;
};

# Public methods
sub admin_navigation_links {
   my ($self, $req, $page) = @_; $page->{selected} //= NUL;

   my $nav  = $self->navigation_links( $req, $page );
   my $list = $nav->{menu}->{list} //= []; $nav->{menu}->{class} = 'dropmenu';
   my $now  = now_dt;

   $self->$_allowed( $req, 'admin/types' )
      and $self->$_admin_links( $req, $page, $nav );

   p_folder $list, 'events', { request => $req, tip => 'Event Menu' };

   p_navlink $list, 'current_events',
      [ 'event/events', [], after => $now->clone->subtract( days => 1 )->ymd ],{
         class   => $_selected_class->( $page, 'current_events' ),
         request => $req };

   p_navlink $list, 'previous_events',
      [ 'event/events', [], before => $now->ymd ], {
         class   => $_selected_class->( $page, 'previous_events' ),
         request => $req };

   $self->$_people_links( $req, $page, $nav );
   $self->$_report_links( $req, $page, $nav );

   p_folder $list, 'training', { request => $req, tip => 'Training Menu' };

   $self->$_allowed( $req, 'train/summary' )
      and p_navlink $list, 'training_summary', [ 'train/summary' ], {
         class => $_selected_class->( $page, 'training' ), request => $req };

   p_navlink $list, 'training_events', [ 'train/events' ], {
      class   => $_selected_class->( $page, 'training_events' ),
      request => $req };

   $self->$_allowed( $req, 'asset/vehicles' )
      and $self->$_vehicle_links( $req, $page, $nav );

   return $nav;
}

sub application_logo {
   my ($self, $req) = @_;

   my $conf   =  $self->config;
   my $logo   =  $conf->logo;
   my $places =  $conf->places;
   my $href   =  $req->uri_for( $conf->images.'/'.$logo->[ 0 ] );
   my $image  =  p_image {}, $conf->title.' Logo', $href, {
      height  => $logo->[ 2 ], width => $logo->[ 1 ] };
   my $opts   =  { request => $req, args => [ $conf->title ], value => $image };

   return p_link {}, 'logo', $req->uri_for_action( $places->{logo} ), $opts;
}

sub call_navigation_links {
   my ($self, $req, $page) = @_; $page->{selected} //= NUL;

   my $nav  = $self->navigation_links( $req, $page );
   my $list = $nav->{menu}->{list} //= [];

   p_folder $list, 'calls', { request => $req };

   p_navlink $list, 'journeys', [ 'call/journeys' ], {
      class => $_selected_class->( $page, 'journeys' ), request => $req };

   p_navlink $list, 'completed',
      [ 'call/journeys', [], status => 'completed' ], {
         class   => $_selected_class->( $page, 'completed_journeys' ),
         request => $req };

   p_navlink $list, 'incidents', [ 'inc/incidents' ], {
      class => $_selected_class->( $page, 'incidents' ), request => $req };

   p_folder $list, 'setup', { request => $req };

   p_navlink $list, 'customers_list', [ 'call/customers' ], {
      class => $_selected_class->( $page, 'customers' ), request => $req };

   p_navlink $list, 'locations_list', [ 'call/locations' ], {
      class => $_selected_class->( $page, 'locations' ), request => $req };

   return $nav;
}

sub credit_links {
   my ($self, $req, $page) = @_; my $list = new_container { type => 'list' };

   my $links = []; my $places = $self->config->places;

   p_link $links, 'about', '#', { class => 'windows', request => $req };

   my $href = $req->uri_for_action( $places->{about} );

   p_js $page, dialog_anchor 'about', $href, { title => locm $req, 'About' };

   p_link $links, 'changes', $req->uri_for_action( $places->{changes} ), {
      request => $req };

   p_text $links, 'recent_activity', $self->activity_cache, {
      class => 'link-help', label_class => 'none',
      label_field_class => 'link-help' };

   p_list $list, PIPE_SEP, $links;

   return $list;
}

sub external_links {
   my ($self, $req) = @_; my $list = new_container { type => 'list' };

   my $links = [];

   for my $link (@{ $self->config->links }) {
      p_link $links, $link->{name}, $link->{url}, {
         request => $req, target => '_blank',
         tip => locm( $req, 'external_link_tip' ), value => $link->{name} };
   }

   p_list $list, PIPE_SEP, $links;

   return $list;
}

sub login_navigation_links {
   my ($self, $req, $page) = @_; $page->{selected} //= NUL;

   my $nav  = $self->navigation_links( $req, $page );
   my $list = $nav->{menu}->{list} //= [];

   p_folder $list, 'login', { request => $req };

   if ($req->authenticated) {
      $self->$_authenticated_login_links( $req, $page, $nav );
   }
   else { $self->$_unauthenticated_login_links( $req, $page, $nav ) }

   return $nav;
}

sub navigation_links {
   my ($self, $req, $page) = @_; my $nav = {};

   $nav->{credits  } = $self->credit_links( $req, $page );
   $nav->{external } = $self->external_links( $req );
   $nav->{logo     } = $self->application_logo( $req );
   $nav->{primary  } = $self->primary_navigation_links( $req, $page );
   $nav->{secondary} = $self->secondary_navigation_links( $req, $page );

   return $nav;
}

sub primary_navigation_links {
   my ($self, $req, $page) = @_;

   my $nav    = new_container { type => 'unordered' };
   my $places = $self->config->places;

   p_navlink $nav, 'documentation', [ 'docs/index' ], {
      class => $_location_class->( $page, 'documentation' ), request => $req };

   $req->authenticated and p_navlink $nav, 'posts', [ 'posts/index' ], {
      class => $_location_class->( $page, 'posts' ), request => $req };

   $req->authenticated or  p_navlink $nav, 'login', [ $places->{login} ], {
      class => $_location_class->( $page, 'login' ), request => $req };

   $req->authenticated or return $nav;

   p_navlink $nav, 'account', [ $places->{profile} ], {
      class   => $_location_class->( $page, 'account_management' ),
      request => $req };

   my $href = $req->uri_for_action( 'user/logout_action' );
   my $form = new_container 'authentication', $href, { class => 'none' };

   p_button $form, 'logout-user', 'logout', {
      class => 'none',
      label => locm( $req, 'Logout' ).' ('.$req->session->user_label.')',
      tip   => make_tip $req, 'Logout from [_1]', [ $self->config->title ] };

   $self->add_csrf_token( $req, $form );

   p_item $nav, $form;

   return $nav;
}

sub rota_navigation_links {
   my ($self, $req, $page, $period, $name) = @_;

   my $nav      = $self->navigation_links( $req, $page );
   my $list     = $nav->{menu}->{list} //= [];
   my $actionp  = "${period}/${period}_rota";
   my $date     = $req->session->rota_date // time2str '%Y-%m-01';
   my $local_dt = local_dt to_dt $date;
   my $f_dom    = $local_dt->clone->set( day => 1 );

   $req->session->rota_date or $self->update_navigation_date( $req, $local_dt );

   p_folder $list, 'year', { request => $req };

   $date = $f_dom->clone->subtract( years => 1 );
   $_p_year_link->( $list, $req, $actionp, $name, $date );
   $_p_year_link->( $list, $req, $actionp, $name, $f_dom, TRUE );
   $date = $f_dom->clone->add( years => 1 );
   $_p_year_link->( $list, $req, $actionp, $name, $date );

   $self->$_rota_month_links( $req, $actionp, $name, $f_dom, $local_dt, $nav );

   my $sow = $local_dt->clone;

   while ($sow->day_of_week > 1) { $sow = $sow->subtract( days => 1 ) }

   $self->$_rota_week_links( $req, $name, $sow, $local_dt, $nav );

   if ($self->$_allowed( $req, 'week/allocation' )) {
      p_folder $list, 'vehicle_allocation', { request => $req };

      $_p_week_link->( $list, $req, 'week/allocation', $name, $sow, {
         local_dt => $local_dt, value => 'spreadsheet' } );
   }

   return $nav;
}

sub secondary_navigation_links {
   my ($self, $req, $page) = @_;

   my $nav = new_container { type => 'unordered' };

   $req->authenticated
      and $self->$_secondary_authenticated_links( $req, $page, $nav );

   return $nav;
}

sub update_navigation_date {
   my ($self, $req, $date) = @_; return $req->session->rota_date( $date->ymd );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::Navigation - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::Navigation;
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
