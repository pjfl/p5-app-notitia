package App::Notitia::Model::Call;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL PRIORITY_TYPE_ENUM
                                PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_action p_button p_fields
                                p_link p_list p_row p_select p_table
                                p_tag p_textfield );
use App::Notitia::Util      qw( check_field_js datetime_label dialog_anchor
                                locm make_tip now_dt page_link_set
                                register_action_paths to_dt to_msg
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'call';

register_action_paths
   'call/customer'  => 'customer',
   'call/customers' => 'customers',
   'call/delivery_stages' => 'delivery-stages',
   'call/journey'   => 'delivery',
   'call/journeys'  => 'deliveries',
   'call/leg'       => 'delivery/*/stage',
   'call/location'  => 'location',
   'call/locations' => 'locations',
   'call/package'   => 'delivery/*/package';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'calls';
   $stash->{navigation} = $self->call_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_add_location_js = sub {
   my ($page, $name) = @_;

   my $opts = { domain => $name ? 'update' : 'insert', form => 'Person' };

   push @{ $page->{literal_js} }, check_field_js( 'postcode', $opts );

   return;
};
my $_customer_tuple = sub {
   my ($selected, $customer) = @_;

   my $opts = { selected => $customer->id == $selected ? TRUE : FALSE };

   return [ $customer->name, $customer->id, $opts ];
};

my $_customers_headers = sub {
   my $req = shift; my $header = 'customers_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 0 ];
};

my $_is_disabled = sub {
   my ($req, $journey, $done) = @_; $journey->id or return $done;

   $req->username ne $journey->controller and return TRUE;
   now_dt > $journey->created->clone->add( minutes => 30 ) and return TRUE;

   return $done;
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

my $_location_tuple = sub {
   my ($selected, $location) = @_;

   my $opts = { selected => $location->id == $selected ? TRUE : FALSE };

   return [ $location->address, $location->id, $opts ];
};

my $_locations_headers = sub {
   my $req = shift; my $header = 'locations_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 0 ];
};

my $_bind_customer = sub {
   my ($customers, $journey) = @_; my $selected = $journey->customer_id;

   return [ [ NUL, undef ],
            map { $_customer_tuple->( $selected, $_ ) } $customers->all ];
};

my $_bind_dropoff_location = sub {
   my ($locations, $journey) = @_; my $selected = $journey->dropoff_id;

   return [ [ NUL, undef ],
            map { $_location_tuple->( $selected, $_ ) } @{ $locations } ];
};

my $_bind_pickup_location = sub {
   my ($locations, $journey) = @_; my $selected = $journey->pickup_id;

   return [ [ NUL, undef ],
            map { $_location_tuple->( $selected, $_ ) } @{ $locations } ];
};

my $_journey_leg_headers = sub {
   my $req = shift; my $header = 'journey_leg_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 4 ];
};

my $_journey_package_headers = sub {
   my $req = shift; my $header = 'journey_package_heading';

   return [ map { { class => $_ == 1 ? 'narrow' : undef,
                    value => locm $req, "${header}_${_}" } } 0 .. 2 ];
};

my $_journeys_header_label = sub {
   my ($req, $done, $index) = @_; my $header = 'journeys_heading';

   $done and $index == 1 and $header = "completed_${header}";

   return { value => locm $req, "${header}_${index}" };
};

my $_journeys_headers = sub {
   my ($req, $done) = @_;

   return [ map { $_journeys_header_label->( $req, $done, $_ ) } 0 .. 3 ];
};

my $_person_tuple = sub {
   my ($selected, $person) = @_;

   my $opts = { selected => $selected == $person->id ? TRUE : FALSE };

   return [ $person->label, $person->id, $opts ];
};

my $_bind_operator = sub {
   my ($leg, $opts) = @_; my $selected = $leg->operator_id;

   return [ [ NUL, undef ],
            map { $_person_tuple->( $selected, $_ ) } $opts->{people}->all ];
};

my $_package_tuple = sub {
   my ($selected, $type) = @_;

   my $opts = { selected => $selected == $type->id ? TRUE : FALSE };

   return [ $type->name, $type->id, $opts ];
};

my $_bind_package_type = sub {
   my ($types, $package) = @_;

   my $selected = $package ? $package->package_type_id : 0; my $other;

   return [ [ NUL, undef ],
            (map  { $_package_tuple->( $selected, $_ ) }
             grep { $_->name eq 'other' and $other = $_; $_->name ne 'other' }
             $types->all), $_package_tuple->( $selected, $other ) ];
};

my $_priority_tuple = sub {
   my ($selected, $priority) = @_; $selected ||= 'routine';

   my $opts = { selected => $selected eq $priority ? TRUE : FALSE };

   return [ $priority, $priority, $opts ];
};

my $_bind_priority = sub {
   my $journey = shift; my $selected = $journey->priority; my $count = 0;

   return [ map { $_priority_tuple->( $selected, $_ ) }
               @{ PRIORITY_TYPE_ENUM() } ];
};

my $_stages_headers = sub {
   my $req = shift; my $header = 'delivery_stages_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 1 ];
};

# Private methods
my $_bind_beginning_location = sub {
   my ($self, $leg, $opts) = @_;

   my $leg_rs   = $self->schema->resultset( 'Leg' );
   my $where    = { journey_id => $opts->{journey_id} };
   my $selected =
        $leg->beginning_id ? $leg->beginning_id
      : $opts->{leg_count} ? ($leg_rs->search( $where )->all)[ -1 ]->ending_id
      :                      $opts->{journey}->pickup_id;

   return [ [ NUL, undef ],
            map { $_location_tuple->( $selected, $_ ) }
               @{ $opts->{locations} } ];
};

my $_bind_customer_fields = sub {
   my ($self, $custer, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;

   return [ name => { disabled => $disabled, label => 'customer_name' } ];
};

my $_bind_ending_location = sub {
   my ($self, $leg, $opts) = @_;

   my $selected = $leg->ending_id || $opts->{journey}->dropoff_id;

   return [ [ NUL, undef ],
            map { $_location_tuple->( $selected, $_ ) }
               @{ $opts->{locations} } ];
};

my $_bind_journey_fields = sub {
   my ($self, $req, $page, $journey, $opts) = @_; $opts //= {};

   my $schema    = $self->schema;
   my $disabled  = $opts->{disabled} // FALSE;
   my $is_viewer = $opts->{is_viewer} // FALSE;
   my $customers = $schema->resultset( 'Customer' )->search( {} );
   my $locations = [ $schema->resultset( 'Location' )->search( {} )->all ];

   return
      [  customer_id   => {
            class      => 'standard-field',
            disabled   => $journey->id ? TRUE : $disabled, type => 'select',
            value      => $_bind_customer->( $customers, $journey ) },
         controller    => $journey->id ? {
            disabled   => TRUE, value => $journey->controller->label } : FALSE,
         requested     => {
            disabled   => $journey->id ? TRUE : $disabled, type => 'datetime',
            value      => $journey->id
                        ? $journey->requested_label : datetime_label now_dt },
         delivered     => $opts->{done} ? {
            disabled   => TRUE, value => $journey->delivered_label } : FALSE,
         priority      => {
            disabled   => $disabled, type => 'radio',
            value      => $_bind_priority->( $journey ) },
         orig_priority => $journey->priority ne $journey->original_priority ? {
            disabled   => TRUE,
            value      => locm $req, $journey->original_priority } : FALSE,
         pickup_id     => {
            class      => 'standard-field',
            disabled   => $disabled, type => 'select',
            value      => $_bind_pickup_location->( $locations, $journey ) },
         dropoff_id    => {
            class      => 'standard-field',
            disabled   => $disabled, type => 'select',
            value      => $_bind_dropoff_location->( $locations, $journey ) },
         notes         => {
            class      => 'standard-field autosize',
            disabled   => $disabled, type => 'textarea' },
      ];
};

my $_bind_leg_fields = sub {
   my ($self, $leg, $opts) = @_; $opts //= {};

   my $schema     = $self->schema;
   my $disabled   = $opts->{disabled} // FALSE;
   my $journey_rs = $schema->resultset( 'Journey' );

   $opts->{journey  } = $journey_rs->find( $opts->{journey_id} );
   $opts->{locations} = [ $schema->resultset( 'Location' )->search( {} )->all ];
   $opts->{people   } = $schema->resultset( 'Person' )->search_for_people( {
      roles => [ 'driver', 'rider' ], status => 'current' } );

   my $on_station_disabled =
      $opts->{request}->username ne $opts->{journey}->controller
      || ($opts->{done} && now_dt > $leg->delivered->clone->add( hours => 24 ))
      ? TRUE : FALSE;

   return
      [  customer_id    => {
            disabled    => TRUE, value => $opts->{journey}->customer },
         operator_id    => {
            class       => 'standard-field',
            disabled    => $leg->id ? TRUE : $disabled, type => 'select',
            value       => $_bind_operator->( $leg, $opts ) },
         called         => {
            disabled    => $leg->id ? TRUE : $disabled,
            value       => $leg->id
                         ? $leg->called_label : datetime_label now_dt },
         beginning_id   => {
            class       => 'standard-field',
            disabled    => $disabled, type => 'select',
            value       =>
               $self->$_bind_beginning_location( $leg, $opts ) },
         ending_id      => {
            class       => 'standard-field',
            disabled    => $disabled, type => 'select',
            value       =>
               $self->$_bind_ending_location( $leg, $opts ) },
         collection_eta => {
            disabled    => $disabled, type => 'datetime',
            value       => $leg->collection_eta_label },
         collected      => $leg->id ? {
            disabled    => $opts->{done}, type => 'datetime',
            value       => $leg->collected_label } : FALSE,
         delivered      => $leg->id ? {
            disabled    => $opts->{done}, type => 'datetime',
            value       => $leg->delivered_label } : FALSE,
         on_station     => $leg->id ? {
            disabled    => $on_station_disabled, type => 'datetime',
            value       => $leg->on_station_label } : FALSE,
      ];
};

my $_bind_location_fields = sub {
   my ($self, $location, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;

   return
      [ address     => { class    => 'standard-field',
                         disabled => $disabled, label => 'location_address' },
        location    => { disabled => $disabled },
        postcode    => { class    => 'standard-field server',
                         disabled => $disabled },
        coordinates => { disabled => $disabled },
        ];
};

my $_count_legs = sub {
   my ($self, $jid) = @_; my $rs = $self->schema->resultset( 'Leg' );

   return $rs->search( { journey_id => $jid } )->count;
};

my $_customers_ops_links = sub {
   my ($self, $req) = @_; my $links = [];

   my $actionp = $self->moniker.'/customer';

   p_link $links, 'customer', uri_for_action( $req, $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_customers_row = sub {
   my ($self, $req, $customer) = @_; my $moniker = $self->moniker;

   my $href = uri_for_action $req, "${moniker}/customer", [ $customer->id ];

   return [ { value => f_link 'customer', $href, {
      request => $req, value => "${customer}" } }, ];
};

my $_find_person = sub {
   my ($self, $scode) = @_; my $rs = $self->schema->resultset( 'Person' );

   return $rs->find_by_shortcode( $scode );
};

my $_delivery_stages = sub {
   my ($self, $scode) = @_;

   my $schema = $self->schema;
   my $where  = { 'delivered'   => { '=' => undef },
                  'operator_id' => $self->$_find_person( $scode )->id };
   my $opts   = { order_by => 'created', prefetch => 'beginning' };

   return [ $schema->resultset( 'Leg' )->search( $where, $opts )->all ];
};

my $_journey_leg_row = sub {
   my ($self, $req, $jid, $leg) = @_;

   my $href = uri_for_action $req, $self->moniker.'/leg', [ $jid, $leg->id ];

   return [ { value => f_link 'leg_operator', $href, {
      request => $req, value => $leg->operator->label } },
            { value => $leg->called_label },
            { value => $leg->beginning },
            { value => $leg->ending },
            { value => locm $req, $leg->status }, ];
};

my $_journey_package_row = sub {
   my ($self, $req, $page, $disabled, $jid, $package) = @_;

   my $actionp = $self->moniker.'/package';
   my $package_type = $package->package_type;
   my $href = uri_for_action $req, $actionp, [ $jid, $package_type ];
   my $title = locm $req, 'Update Package Details';
   my $name = "update_${package_type}_package";
   my $value = locm $req, $package_type;
   my $tip = locm $req, 'update_package_tip';

   push @{ $page->{literal_js} }, dialog_anchor( $name, $href, {
      name => $name, title => $title, } );

   return
      [ { class  => 'narrow', value => $package->quantity },
        { value  => $disabled ? $value : f_link $name, '#', {
           class => 'windows', request => $req, tip => $tip,
           value => $value } },
        { value  => $package->description }, ];
};

my $_journey_leg_ops_links = sub {
   my ($self, $req, $jid) = @_; my $links = []; $jid or return $links;

   my $actionp = $self->moniker.'/leg';

   p_link $links, 'leg', uri_for_action( $req, $actionp, [ $jid ] ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_journey_package_ops_links = sub {
   my ($self, $req, $page, $jid) = @_; my $links = []; $jid or return $links;

   my $actionp = $self->moniker.'/package';
   my $tip = locm $req, 'journey_package_add_tip';
   my $value = locm $req, 'Add Package';
   my $title = locm $req, 'Add Package Details';

   p_link $links, 'package', '#', {
      action => 'create', class => 'windows', container_class => 'add-link',
      request => $req, tip => $tip, value => $value };

   my $href = uri_for_action $req, $actionp, [ $jid ];

   push @{ $page->{literal_js} }, dialog_anchor( 'create_package', $href, {
      name => 'create_package', title => $title, } );

   return $links;
};

my $_journeys_ops_links = sub {
   my ($self, $req, $page, $params, $pager, $done) = @_; my $links = [];

   my $actionp = $self->moniker.'/journeys';
   my $page_links = page_link_set $req, $actionp, [], $params, $pager;

   $page_links and push @{ $links }, $page_links;

   unless ($done) {
      my $name = 'delivery_stages';
      my $actionp = $self->moniker."/${name}";
      my $href = uri_for_action $req, $actionp, [ $req->username ];
      my $title = locm( $req, "${name}_title" );

      p_link $links, $name, '#', { class => 'windows', request => $req };
      push @{ $page->{literal_js} }, dialog_anchor( $name, $href, {
         name => $name, title => $title, } );

      $actionp = $self->moniker.'/journey';
      p_link $links, 'journey', uri_for_action( $req, $actionp ), {
         action => 'create', container_class => 'add-link', request => $req };
   }

   return $links;
};

my $_journeys_row = sub {
   my ($self, $req, $done, $journey) = @_;

   my $href = uri_for_action $req, $self->moniker.'/journey', [ $journey->id ];
   my $package = ($journey->packages->all)[ 0 ];

   return [ { value => f_link 'delivery_request', $href, {
      request => $req, value => $journey->customer, } },
            { value => $done ? $journey->delivered_label
                             : $journey->requested_label },
            { value => locm $req, $journey->priority },
            { value => locm $req, $package ? $package->package_type : NUL }, ];
};

my $_leg_ops_links = sub {
   my ($self, $req, $page, $jid) = @_; my $links = [];

   my $actionp = $self->moniker.'/journey';

   p_link $links, 'journey', uri_for_action( $req, $actionp, [ $jid ] ), {
      action => 'view', container_class => 'table-link', request => $req };

   return $links;
};

my $_locations_ops_links = sub {
   my ($self, $req) = @_; my $links = [];

   my $actionp = $self->moniker.'/location';

   p_link $links, 'location', uri_for_action( $req, $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_locations_row = sub {
   my ($self, $req, $location) = @_; my $moniker = $self->moniker;

   my $href = uri_for_action $req, "${moniker}/location", [ $location->id ];

   return [ { value => f_link 'location', $href, {
      request => $req, value => "${location}" } }, ];
};

my $_maybe_find = sub {
   my ($self, $class, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( $class )->find( $id );
};

my $_maybe_find_package = sub {
   my ($self, $type_rs, $journey_id, $package_type) = @_;

   $package_type or return Class::Null->new;

   my $package_rs = $self->schema->resultset( 'Package' );
   my $package_type_id = $type_rs->find_package_by( $package_type )->id;

   return $package_rs->find( $journey_id, $package_type_id );
};

my $_packages_and_stages = sub {
   my ($self, $req, $page, $disabled, $jid) = @_;

   my $pform = $page->{forms}->[ 1 ];

   p_tag $pform, 'h5', locm $req, 'journey_package_title';

   my $links = $self->$_journey_package_ops_links( $req, $page, $jid );

   $disabled or p_list $pform, PIPE_SEP, $links, $_link_opts->();

   my $package_rs = $self->schema->resultset( 'Package' );
   my $packages = $package_rs->search( { journey_id => $jid }, {
      order_by => { -desc => 'quantity' } } );
   my $p_table = p_table $pform, {
      headers => $_journey_package_headers->( $req ) };

   p_row $p_table, [ map {
      $self->$_journey_package_row( $req, $page, $disabled, $jid, $_ ) }
                     $packages->all ];

   my $lform = $page->{forms}->[ 2 ];

   p_tag $lform, 'h5', locm $req, 'journey_leg_title';

   $links = $self->$_journey_leg_ops_links( $req, $jid );

   $disabled or p_list $lform, PIPE_SEP, $links, $_link_opts->();

   my $leg_rs  = $self->schema->resultset( 'Leg' );
   my $legs    = $leg_rs->search( { journey_id => $jid } );
   my $l_table = p_table $lform, { headers => $_journey_leg_headers->( $req ) };

   p_row $l_table, [ map { $self->$_journey_leg_row( $req, $jid, $_ ) }
                     $legs->all ];

   return;
};

my $_send_stage_events = sub {
   my ($self, $req, $journey, $leg, $completed, $params) = @_;

   my $jid = $journey->id;
   my $lid = $leg->id;
   my $status = $leg->status;
   my $c_tag = lc $journey->customer->name; $c_tag =~ s{ [ ] }{_}gmx;
   my $message = "action:update-delivery-stage delivery_id:${jid} "
               . "stage_id:${lid} status:${status} customer:${c_tag}";

   $self->send_event( $req, $message, $params );

   $completed and $message = "action:delivery-complete delivery_id:${jid} "
                           . "customer:${c_tag}"
              and $self->send_event( $req, $message, $params );
   return;
};

my $_stages_row = sub {
   my ($self, $req, $stage) = @_;

   my $jid = $stage->journey_id;
   my $actionp = $self->moniker.'/leg';
   my $href = uri_for_action $req, $actionp, [ $jid, $stage->id ];
   my $tip  = locm $req, 'stages_row_link_tip';
   my $cell0 = {};

   p_link $cell0, 'stage_'.$stage->id, $href, {
      request => $req, tip => $tip, value => $stage->label( $req ) };

   my $form = blank_form 'leg', $href;
   my $status = $stage->status;

   $status eq 'on_station'
      and return [ $cell0, { value => locm $req, $status } ];

   my $name = $status eq 'delivered' ? 'update_stage_on_station'
            : $status eq 'collected' ? 'update_stage_delivered'
            : 'update_stage_collected';

   $tip = make_tip $req, "${name}_tip";
   p_button $form, $name, $name, { class => 'save-button', tip => $tip };

   return [ $cell0, { value => $form } ];
};

my $_update_journey_from_request = sub {
   my ($self, $req, $journey) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( customer_id dropoff_id notes
                     pickup_id priority requested )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      if (length $v and is_member $attr, [ qw( requested ) ]) {
         $v =~ s{ [@] }{}mx; $v = to_dt $v;
      }

      $journey->$attr( $v );
   }

   $journey->controller_id( $self->$_find_person( $req->username )->id );

   return;
};

my $_update_leg_from_request = sub {
   my ($self, $req, $leg, $supplied) = @_; $supplied //= {};

   my $params = $req->body_params; my $opts = { optional => TRUE };

   for my $attr (qw( beginning_id called collection_eta collected delivered
                     ending_id on_station operator_id )) {
      my $v = $supplied->{ $attr } // $params->( $attr, $opts );

      defined $v or next; $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      $attr eq 'operator_id' and not $v and next;

      if (length $v and is_member $attr,
          [ qw( called collection_eta collected delivered on_station ) ]) {
         $v =~ s{ [@] }{}mx; $v = to_dt $v;
      }

      $leg->$attr( $v );
   }

   $leg->on_station
      and (not $leg->delivered or $leg->delivered > $leg->on_station)
      and throw 'Cannot return to station before package delivered';
   $leg->delivered
      and (not $leg->collected or $leg->collected > $leg->delivered)
      and throw 'Cannot deliver package before collecting it';
   return;
};

my $_update_location_from_request = sub {
   my ($self, $req, $location, $supplied) = @_; my $params = $req->body_params;

   for my $attr (qw( address coordinates location postcode )) {
      my $v = $supplied->{ $attr } // $params->( $attr, { optional => TRUE } );

      (defined $v and length $v) or next;
      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;
      $location->$attr( $v );
   }

   return;
};

my $_update_package_from_request = sub {
   my ($self, $req, $package) = @_; my $params = $req->body_params;

   for my $attr (qw( description package_type quantity )) {
      my $v = $params->( $attr, { optional => TRUE } ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      my $method = $attr; $attr eq 'package_type' and $method .= '_id';

      $package->$method( $v );
   }

   return;
};

# Public methods
sub create_customer_action : Role(controller) {
   my ($self, $req) = @_;

   my $name     = $req->body_params->( 'name' );
   my $rs       = $self->schema->resultset( 'Customer' );
   my $cid      = $rs->create( { name => $name } )->id;
   my $key      = 'Customer [_1] created by [_2]';
   my $message  = [ to_msg $key, $cid, $req->session->user_label ];
   my $location = uri_for_action $req, $self->moniker.'/customers';

   return { redirect => { location => $location, message => $message } };
}

sub create_delivery_request_action : Role(controller) {
   my ($self, $req) = @_;

   my $schema   = $self->schema;
   my $cid      = $req->body_params->( 'customer_id' );
   my $customer = $schema->resultset( 'Customer' )->find( $cid );
   my $journey  = $schema->resultset( 'Journey' )->new_result( {} );

   $self->$_update_journey_from_request( $req, $journey );

   try   { $journey->insert }
   catch { $self->rethrow_exception
              ( $_, 'create', 'delivery request', $customer->name ) };

   my $jid = $journey->id;
   my $c_tag = lc $customer->name; $c_tag =~ s{ [ ] }{_}gmx;
   my $message = "action:create-delivery delivery_id:${jid} customer:${c_tag}";

   $self->send_event( $req, $message );

   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];
   my $key = 'Package type [_1] for delivery request [_2] deleted by [_3]';

   $message = [ to_msg $key, $jid, $customer->name, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub create_delivery_stage_action : Role(controller) {
   my ($self, $req) = @_;

   my $jid = $req->uri_params->( 0 );
   my $rs  = $self->schema->resultset( 'Leg' );
   my $leg = $rs->new_result( { journey_id => $jid } );

   $self->$_update_leg_from_request( $req, $leg );

   try   { $leg->insert }
   catch { $self->rethrow_exception( $_, 'create', 'delivery stage', $jid ) };

   my $key = 'Stage [_1] of delivery request [_2] created by [_3]';
   my $message = [ to_msg $key, $leg->id, $jid, $req->session->user_label ];
   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];

   return { redirect => { location => $location, message => $message } };
}

sub create_location_action : Role(controller) {
   my ($self, $req, $params) = @_; $params //= {};

   my $address  = $params->{address} // $req->body_params->( 'address' );
   my $rs = $self->schema->resultset( 'Location' );
   my $location = $rs->new_result( {} );

   $self->$_update_location_from_request( $req, $location, $params );
   $location->insert;

   my $lid = $location->id;
   my $message = "action:create-location location_id:${lid}";

   $self->send_event( $req, $message, $params );

   my $key = 'Location [_1] created by [_2]';

   $message = [ to_msg $key, $lid, $req->session->user_label ];
   $location = uri_for_action $req, $self->moniker.'/locations';

   return { redirect => { location => $location, message => $message } };
}

sub create_package_action : Role(controller) {
   my ($self, $req) = @_;

   my $journey_id = $req->uri_params->( 0 );
   my $package = $self->schema->resultset( 'Package' )->new_result( {
      journey_id => $journey_id } );

   $self->$_update_package_from_request( $req, $package );

   my $type = $package->package_type || NUL;

   try   { $package->insert }
   catch { $self->rethrow_exception( $_, 'create', 'package', $type ) };

   my $message = "action:create-package delivery_id:${journey_id} "
               . "package_type:${type}";

   $self->send_event( $req, $message );

   my $actionp = $self->moniker.'/journey';
   my $location = uri_for_action $req, $actionp, [ $journey_id ];
   my $key = 'Package type [_1] for delivery request [_2] created by [_3]';

   $message = [ to_msg $key, $type, $journey_id, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
};

sub customer : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $cid     =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/customer', [ $cid ];
   my $form    =  blank_form 'customer', $href;
   my $action  =  $cid ? 'update' : 'create';
   my $page    =  {
      first_field => 'name', forms => [ $form ], selected => 'customers',
      title    => locm $req, 'customer_setup_title'
   };
   my $custer  =  $self->$_maybe_find( 'Customer', $cid );

   p_fields $form, $self->schema, 'Customer', $custer,
      $self->$_bind_customer_fields( $custer, {} );

   p_action $form, $action, [ 'customer', $cid ], { request => $req };

   $cid and p_action $form, 'delete', [ 'customer', $cid ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub customers : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $form = blank_form { class => 'standard-form' };
   my $page = {
      forms => [ $form ], selected => 'customers',
      title => locm $req, 'customers_list_title'
   };
   my $links = $self->$_customers_ops_links( $req );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, { headers => $_customers_headers->( $req ) };
   my $customers = $self->schema->resultset( 'Customer' )->search( {} );

   p_row $table, [ map { $self->$_customers_row( $req, $_ ) } $customers->all ];

   return $self->get_stash( $req, $page );
}

sub delete_customer_action : Role(controller) {
   my ($self, $req) = @_;

   my $cid = $req->uri_params->( 0 );
   my $custer = $self->schema->resultset( 'Customer' )->find( $cid );

   $custer->delete;

   my $who = $req->session->user_label;
   my $message = [ to_msg 'Customer [_1] deleted by [_2]', $cid, $who ];
   my $location = uri_for_action $req, $self->moniker.'/customers';

   return { redirect => { location => $location, message => $message } };
}

sub delete_delivery_request_action : Role(controller) {
   my ($self, $req) = @_;

   my $jid = $req->uri_params->( 0 );
   my $journey = $self->schema->resultset( 'Journey' )->find( $jid );
   my $c_tag = lc $journey->customer->name; $c_tag =~ s{ [ ] }{_}gmx;

   $journey->delete;

   my $message = "action:delete-delivery delivery_id:${jid} customer:${c_tag}";

   $self->send_event( $req, $message );

   my $who = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/journeys';

   $message = [ to_msg 'Delivery request [_1] deleted by [_2]', $jid, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_delivery_stage_action : Role(controller) {
   my ($self, $req) = @_;

   my $jid      = $req->uri_params->( 0 );
   my $lid      = $req->uri_params->( 1 );
   my $leg      = $self->schema->resultset( 'Leg' )->find( $lid ); $leg->delete;
   my $key      = 'Stage [_1] of delivery request [_2] deleted by [_3]';
   my $message  = [ to_msg $key, $lid, $jid, $req->session->user_label ];
   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_location_action : Role(controller) {
   my ($self, $req) = @_;

   my $lid = $req->uri_params->( 0 );
   my $location = $self->schema->resultset( 'Location' )->find( $lid );

   $location->delete;

   my $who = $req->session->user_label;
   my $message = [ to_msg 'Location [_1] deleted by [_2]', $lid, $who ];

   $location = uri_for_action $req, $self->moniker.'/locations';

   return { redirect => { location => $location, message => $message } };
}

sub delete_package_action : Role(controller) {
   my ($self, $req) = @_;

   my $journey_id = $req->uri_params->( 0 );
   my $package_type = $req->uri_params->( 1 );
   my $type_rs = $self->schema->resultset( 'Type' );
   my $package = $self->$_maybe_find_package
      ( $type_rs, $journey_id, $package_type );

   $package->delete;

   my $message = "action:delete-package delivery_id:${journey_id} "
               . "package_type:${package_type}";

   $self->send_event( $req, $message );

   my $actionp = $self->moniker.'/journey';
   my $location = uri_for_action $req, $actionp, [ $journey_id ];
   my $key = 'Package type [_1] for delivery request [_2] deleted by [_3]';

   $message = [ to_msg $key, $package_type,
                $journey_id, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub delivery_stages : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $stash = $self->dialog_stash( $req );
   my $form  = $stash->{page}->{forms}->[ 0 ] = blank_form;
   my $table = p_table $form, { headers => $_stages_headers->( $req ) };

   for my $stage (@{ $self->$_delivery_stages( $scode ) }) {
      p_row $table, $self->$_stages_row( $req, $stage );
   }

   return $stash;
}

sub journey : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $jid     =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/journey', [ $jid ];
   my $jform   =  blank_form 'journey', $href;
   my $pform   =  blank_form { class => 'wide-form' };
   my $lform   =  blank_form { class => 'wide-form' };
   my $action  =  $jid ? 'update' : 'create';
   my $journey =  $self->$_maybe_find( 'Journey', $jid );
   my $done    =  $jid && $journey->completed ? TRUE : FALSE;
   my $page    =  {
      forms    => [ $jform, $pform, $lform ],
      selected => $done ? 'completed_journeys' : 'journeys',
      title    => locm $req, 'journey_call_title'
   };
   my $disabled  = $_is_disabled->( $req, $journey, $done );
   my $is_viewer = is_member 'call_viewer', $req->session->roles;
   my $label     = locm( $req, 'delivery request' ).SPC.($jid // NUL);

   p_fields $jform, $self->schema, 'Journey', $journey,
      $self->$_bind_journey_fields( $req, $page, $journey, {
         disabled => $disabled, done => $done, is_viewer => $is_viewer } );

   $disabled or p_action $jform, $action, [ 'delivery_request', $label ], {
      request => $req };

   (not $is_viewer and $disabled) or $done
      or ($jid and p_action $jform, 'delete', [ 'delivery_request', $label ], {
         request => $req } );

   $jid and $self->$_packages_and_stages( $req, $page, $disabled, $jid );

   return $self->get_stash( $req, $page );
}

sub journeys : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $params =  $req->query_params->( { optional => TRUE } );
   my $status =  $params->{status} // NUL;
   my $done   =  $status eq 'completed' ? TRUE : FALSE;
   my $select =  $done ? 'completed_journeys' : 'journeys';
   my $form   =  blank_form;
   my $page   =  {
      forms   => [ $form ], selected => $select,
      title   => locm $req, "${select}_title",
   };
   my $is_viewer =  is_member 'call_viewer', $req->session->roles;
   my $opts      =  {
      controller => $req->username,
      done       => $done,
      is_viewer  => $is_viewer,
      page       => delete $params->{page} // 1,
      rows       => $req->session->rows_per_page,
   };
   my $rs        =  $self->schema->resultset( 'Journey' );
   my $journeys  =  $rs->search_for_journeys( $opts );
   my $links     =  $self->$_journeys_ops_links
      ( $req, $page, $params, $journeys->pager, $done );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, { headers => $_journeys_headers->( $req, $done )};

   p_row $table, [ map { $self->$_journeys_row( $req, $done, $_ ) }
                   $journeys->all ];

   return $self->get_stash( $req, $page );
}

sub leg : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $jid     =  $req->uri_params->( 0 );
   my $lid     =  $req->uri_params->( 1, { optional => TRUE } );
   my $journey =  $self->$_maybe_find( 'Journey', $jid );
   my $leg     =  $self->$_maybe_find( 'Leg', $lid );
   my $done    =  $lid && $leg->delivered ? TRUE : FALSE;
   my $href    =  uri_for_action $req, $self->moniker.'/leg', [ $jid, $lid ];
   my $action  =  $lid ? 'update' : 'create';
   my $form    =  blank_form 'leg', $href;
   my $page    =  {
      forms    => [ $form ], selected => $done ? 'completed' : 'journeys',
      title    => locm $req, 'journey_leg_title'
   };
   my $links    = $self->$_leg_ops_links( $req, $page, $jid );
   my $count    = !$lid ? $self->$_count_legs( $jid ) : undef;
   my $disabled = $_is_disabled->( $req, $journey, $done );
   my $label    = locm( $req, 'stage' ).SPC.($lid // NUL);

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_fields $form, $self->schema, 'Leg', $leg, $self->$_bind_leg_fields( $leg, {
      disabled => $disabled, done => $done,
      journey_id => $jid, leg_count => $count, request => $req } );

   ($done and $leg->on_station)
      or p_action $form, $action, [ 'delivery_stage', $label ], {
         request => $req };

   $disabled or ($lid and
      p_action $form, 'delete', [ 'delivery_stage', $label ], {
         request => $req } );

   return $self->get_stash( $req, $page );
}

sub location : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $lid = $req->uri_params->( 0, { optional => TRUE } );
   my $href = uri_for_action $req, $self->moniker.'/location', [ $lid ];
   my $form = blank_form 'location', $href;
   my $action = $lid ? 'update' : 'create';
   my $page = {
      first_field => 'address', forms => [ $form ], selected => 'locations',
      title => locm $req, 'location_setup_title'
   };
   my $where = $self->$_maybe_find( 'Location', $lid );

   p_fields $form, $self->schema, 'Location', $where,
      $self->$_bind_location_fields( $where, {} );

   p_action $form, $action, [ 'location', $lid ], { request => $req };

   $lid and p_action $form, 'delete', [ 'location', $lid ], { request => $req };

   $_add_location_js->( $page, $lid );

   return $self->get_stash( $req, $page );
}

sub locations : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $form = blank_form { class => 'standard-form' };
   my $page = {
      forms => [ $form ], selected => 'locations',
      title => locm $req, 'locations_list_title'
   };
   my $links = $self->$_locations_ops_links( $req );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, { headers => $_locations_headers->( $req ) };
   my $locations = $self->schema->resultset( 'Location' )->search( {} );

   p_row $table, [ map { $self->$_locations_row( $req, $_ ) } $locations->all ];

   return $self->get_stash( $req, $page );
}

sub package : Role(controller) {
   my ($self, $req) = @_;

   my $journey_id = $req->uri_params->( 0 );
   my $package_type = $req->uri_params->( 1, { optional => TRUE } );
   my $action = $package_type ? 'update' : 'create';
   my $stash = $self->dialog_stash( $req );
   my $actionp = $self->moniker.'/package';
   my $href = uri_for_action $req, $actionp, [ $journey_id, $package_type ];
   my $form = $stash->{page}->{forms}->[ 0 ] = blank_form 'package', $href;
   my $type_rs = $self->schema->resultset( 'Type' );
   my $types = $type_rs->search_for_package_types;
   my $label = locm( $req, 'delivery request' )." ${journey_id}";
   my $package = $self->$_maybe_find_package
      ( $type_rs, $journey_id, $package_type );
   my $disabled = $package_type ? TRUE : FALSE;

   p_select $form, 'quantity', [ map { [ $_, $_, {
      selected => $_ == $package->quantity ? TRUE : FALSE } ] } 1 .. 9 ], {
         class => 'single-digit', };

   p_select $form, 'package_type', $_bind_package_type->( $types, $package ), {
      class => 'standard-field', disabled => $disabled, };

   p_textfield $form, 'description', $package->description;

   p_action $form, $action, [ 'package', $label ], { request => $req };

   $package_type and p_action $form, 'delete', [ 'package', $label ], {
      request => $req };

   return $stash;
}

sub update_customer_action : Role(controller) {
   my ($self, $req) = @_;

   my $cid = $req->uri_params->( 0 );
   my $custer = $self->schema->resultset( 'Customer' )->find( $cid );

   $custer->name( $req->body_params->( 'name' ) ); $custer->update;

   my $who = $req->session->user_label;
   my $message = [ to_msg 'Customer [_1] updated by [_2]', $cid, $who ];
   my $location = uri_for_action $req, $self->moniker.'/customers';

   return { redirect => { location => $location, message => $message } };
}

sub update_delivery_request_action : Role(controller) {
   my ($self, $req) = @_;

   my $jid     = $req->uri_params->( 0 );
   my $journey = $self->schema->resultset( 'Journey' )->find( $jid );
   my $c_name  = $journey->customer->name;

   $journey->controller eq $req->username
      or throw 'Updating someone elses delivery request is not allowed';

   $self->$_update_journey_from_request( $req, $journey );

   try   { $journey->update }
   catch { $self->rethrow_exception
              ( $_, 'update', 'delivery request', $c_name ) };

   my $c_tag = lc $c_name; $c_tag =~ s{ [ ] }{_}gmx;
   my $message = "action:update-delivery delivery_id:${jid} customer:${c_tag}";

   $self->send_event( $req, $message );

   $message = [ to_msg 'Delivery request [_1] for [_2] updated by [_3]',
                $jid, $c_name, $req->session->user_label ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_delivery_stage_action : Role(controller) Role(driver) Role(rider) {
   my ($self, $req, $params) = @_; $params //= {};

   my $schema    = $self->schema;
   my $jid       = $req->uri_params->( 0 );
   my $lid       = $req->uri_params->( 1 );
   my $journey   = $schema->resultset( 'Journey' )->find( $jid );
   my $leg       = $schema->resultset( 'Leg' )->find( $lid );
   my $delivered = $leg->delivered;

   $journey->controller eq $req->username
      or $leg->operator eq $req->username
      or throw 'Updating someone elses delivery stage is not allowed';

   $self->$_update_leg_from_request( $req, $leg, $params );

   my $completed = FALSE; not $delivered and $leg->delivered
      and $leg->ending_id == $journey->dropoff_id
      and $completed = TRUE;

   my $update = sub {
      $leg->update;
      $completed and $journey->completed( TRUE )
                 and $journey->delivered( $leg->delivered )
                 and $journey->update;
   };

   try   { $self->schema->txn_do( $update ) }
   catch { $self->rethrow_exception( $_, 'update', 'delivery stage', $lid ) };

   $self->$_send_stage_events( $req, $journey, $leg, $completed, $params );

   my $key = 'Stage [_1] of delivery request [_2] updated by [_3]';
   my $message = [ to_msg $key, $lid, $jid, $req->session->user_label ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_location_action : Role(controller) {
   my ($self, $req, $params) = @_; $params //= {};

   my $lid = $params->{location_id} // $req->uri_params->( 0 );
   my $location = $self->schema->resultset( 'Location' )->find( $lid );

   $self->$_update_location_from_request( $req, $location, $params );
   $location->update;

   my $message = "action:update-location location_id:${lid}";

   $self->send_event( $req, $message, $params );

   my $key = 'Location [_1] updated by [_2]';

   $message = [ to_msg $key, $lid, $req->session->user_label ];
   $location = uri_for_action $req, $self->moniker.'/locations';

   return { redirect => { location => $location, message => $message } };
}

sub update_package_action : Role(controller) {
   my ($self, $req) = @_;

   my $journey_id = $req->uri_params->( 0 );
   my $package_type = $req->uri_params->( 1 );
   my $type_rs = $self->schema->resultset( 'Type' );
   my $package = $self->$_maybe_find_package
      ( $type_rs, $journey_id, $package_type );

   $self->$_update_package_from_request( $req, $package );
   $package->update;

   my $message = "action:update-package delivery_id:${journey_id} "
               . "package_type:${package_type}";

   $self->send_event( $req, $message );

   my $actionp = $self->moniker.'/journey';
   my $location = uri_for_action $req, $actionp, [ $journey_id ];
   my $key = 'Package type [_1] for delivery request [_2] updated by [_3]';
   my $who = $req->session->user_label;

   $message = [ to_msg $key, $package_type, $journey_id, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub update_stage_collected_action : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $stash = $self->update_delivery_stage_action
      ( $req, { collected => datetime_label now_dt } );

   return $stash;
}

sub update_stage_delivered_action : Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $stash = $self->update_delivery_stage_action
      ( $req, { delivered => datetime_label now_dt } );

   return $stash;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Call - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Call;
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
