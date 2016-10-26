package App::Notitia::Model::Call;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL PRIORITY_TYPE_ENUM
                                PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link f_tag p_action p_button
                                p_container p_fields p_link p_list p_row
                                p_select p_table p_tag p_textfield );
use App::Notitia::Util      qw( datetime_label dialog_anchor js_window_config
                                locm make_tip now_dt page_link_set
                                register_action_paths to_dt
                                to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_arrayref is_member throw );
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
   'call/incident_party' => 'incident/*/parties',
   'call/customer'       => 'customer',
   'call/customers'      => 'customers',
   'call/incident'       => 'incident',
   'call/incidents'      => 'incidents',
   'call/journey'        => 'delivery',
   'call/journeys'       => 'deliveries',
   'call/leg'            => 'delivery/*/stage',
   'call/location'       => 'location',
   'call/locations'      => 'locations',
   'call/package'        => 'delivery/*/package';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'calls';
   $stash->{navigation} = $self->call_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_category_tuple = sub {
   my ($selected, $category) = @_;

   my $opts = { selected => $selected == $category->id ? TRUE : FALSE };

   return [ $category->name, $category->id, $opts ];
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

my $_incidents_headers = sub {
   my $req = shift; my $header = 'incidents_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 2 ];
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

my $_bind_call_category = sub {
   my ($categories, $incident) = @_;

   my $selected = $incident->category_id; my $other;

   return [ [ NUL, undef ],
            (map  { $_category_tuple->( $selected, $_ ) }
             grep { $_->name eq 'other' and $other = $_; $_->name ne 'other' }
             $categories->all), $_category_tuple->( $selected, $other ) ];
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

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 3 ];
};

my $_journey_package_headers = sub {
   my $req = shift; my $header = 'journey_package_heading';

   return [ map { { class => $_ == 1 ? 'narrow' : undef,
                    value => locm $req, "${header}_${_}" } } 0 .. 2 ];
};

my $_journeys_headers = sub {
   my $req = shift; my $header = 'journeys_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 3 ];
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

my $_subtract = sub {
   return [ grep { not is_member $_->[ 1 ], [ map { $_->[ 1 ] } @{ $_[ 1 ] } ] }
                @{ $_[ 0 ] } ];
};

# Private methods
my $_incident_party_ops_links = sub {
   my ($self, $req, $page, $iid) = @_; my $links = [];

   my $actionp = $self->moniker.'/incident';

   p_link $links, 'incident', uri_for_action( $req, $actionp, [ $iid ] ), {
      action => 'view', container_class => 'table-link', request => $req };

   return $links;
};

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

my $_bind_committee_member = sub {
   my ($self, $incident) = @_;

   my $selected = $incident->committee_member_id || 0;
   my $rs = $self->schema->resultset( 'Person' );
   my $opts = { role => 'committee', status => 'current', };

   return [ [ NUL, undef ],
            map { $_person_tuple->( $selected, $_ ) }
            $rs->search_for_people( $opts ) ];
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

my $_bind_incident_fields = sub {
   my ($self, $page, $incident, $opts) = @_; $opts //= {};

   my $schema = $self->schema;
   my $disabled = $opts->{disabled} // FALSE;
   my $type_rs = $schema->resultset( 'Type' );
   my $categories = $type_rs->search_for_call_categories;
   my $other_type_id = $type_rs->search( {
      name => 'other', type_class => 'call_category', } )->first->id;

   push @{ $page->{literal_js} }, js_window_config 'category', 'change',
      'showIfNeeded', [ 'category', $other_type_id, 'category_other_field' ];

   return
      [  controller     => $incident->id ? {
            disabled    => TRUE,
            value       => $incident->controller->label } : FALSE,
         raised         => $incident->id ? {
            disabled    => TRUE, value => $incident->raised_label } : FALSE,
         title          => {
            class       => 'standard-field',
            disabled    => $disabled, label => 'incident_title' },
         reporter       => { class => 'standard-field', disabled => $disabled },
         reporter_phone => { disabled => $disabled },
         category_id    => {
            class       => 'standard-field windows',
            disabled    => $disabled, id => 'category',
            label       => 'call_category', type => 'select',
            value       => $_bind_call_category->( $categories, $incident ) },
         category_other => {
            disabled    => $disabled,
            label_class => $incident->id && $incident->category eq 'other'
                         ? NUL : 'hidden',
            label_id    => 'category_other_field' },
         notes          => {
            class       => 'standard-field autosize',
            disabled    => $disabled, type => 'textarea' },
         committee_informed => $incident->id ? {
            disabled    => $disabled, type => 'datetime',
            value       => $incident->committee_informed_label } : FALSE,
         committee_member_id => $incident->id ? {
            disabled    => $disabled,
            label       => 'committee_member', type => 'select',
            value       => $self->$_bind_committee_member( $incident )} : FALSE,
       ];
};

my $_bind_journey_fields = sub {
   my ($self, $req, $page, $journey, $opts) = @_; $opts //= {};

   my $schema    = $self->schema;
   my $disabled  = $opts->{disabled} // FALSE;
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

   return [ address => { disabled => $disabled, label => 'location_address' } ];
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

my $_incident_ops_links = sub {
   my ($self, $req, $iid) = @_; my $links = [];

   my $actionp = $self->moniker.'/incident_party';
   my $href = uri_for_action $req, $actionp, [ $iid ];

   p_link $links, 'incident_party', $href, {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_incidents_ops_links = sub {
   my ($self, $req, $page, $params, $pager) = @_; my $links = [];

   my $actionp = $self->moniker.'/incident';

   p_link $links, 'incident', uri_for_action( $req, $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   $actionp = $self->moniker.'/incidents';

   my $page_links = page_link_set $req, $actionp, [], $params, $pager;

   $page_links and push @{ $links }, $page_links;

   return $links;
};

my $_incidents_row = sub {
   my ($self, $req, $incident) = @_;

   my $href = uri_for_action $req, $self->moniker.'/incident', [ $incident->id];

   return [ { value => f_link 'incident_record', $href, {
      request => $req, value => $incident->title, } },
            { value => $incident->raised_label },
            { value => locm $req, $incident->category }, ];
};

my $_journey_leg_row = sub {
   my ($self, $req, $jid, $leg) = @_;

   my $href = uri_for_action $req, $self->moniker.'/leg', [ $jid, $leg->id ];

   return [ { value => f_link 'leg_operator', $href, {
      request => $req, value => $leg->operator->label } },
            { value => $leg->called_label },
            { value => $leg->beginning },
            { value => $leg->ending }, ];
};

my $_journey_package_row = sub {
   my ($self, $req, $page, $done, $jid, $package) = @_;

   my $actionp = $self->moniker.'/package';
   my $package_type = $package->package_type;
   my $href = uri_for_action $req, $actionp, [ $jid, $package_type ];
   my $title = locm $req, 'Update Package Details';
   my $id = "update_${package_type}_package";
   my $value = locm $req, $package_type;
   my $tip = locm $req, 'update_package_tip';

   push @{ $page->{literal_js} }, dialog_anchor( $id, $href, {
      name => $id, title => $title, useIcon => \1 } );

   return
      [ { class  => 'narrow', value => $package->quantity },
        { value  => $done ? $value : f_link $id, '#', {
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
      name => 'create_package', title => $title, useIcon => \1 } );

   return $links;
};

my $_journeys_ops_links = sub {
   my ($self, $req, $page, $params, $pager, $done) = @_; my $links = [];

   my $actionp = $self->moniker.'/journey';

   $done or p_link $links, 'journey', uri_for_action( $req, $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   $actionp = $self->moniker.'/journeys';

   my $page_links = page_link_set $req, $actionp, [], $params, $pager;

   $page_links and push @{ $links }, $page_links;

   return $links;
};

my $_journeys_row = sub {
   my ($self, $req, $journey) = @_;

   my $href = uri_for_action $req, $self->moniker.'/journey', [ $journey->id ];
   my $package = ($journey->packages->all)[ 0 ];

   return [ { value => f_link 'delivery_request', $href, {
      request => $req, value => $journey->customer, } },
            { value => $journey->requested_label },
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

my $_list_all_people = sub {
   my $self = shift; my $rs = $self->schema->resultset( 'Person' );

   return [ map { [ $_->label, $_->shortcode ] } $rs->search( {} )->all ];
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

my $_update_incident_from_request = sub {
   my ($self, $req, $incident) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( category_id title reporter reporter_phone category_other
                     notes committee_informed committee_member_id )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      if (length $v and is_member $attr, [ qw( committee_informed ) ]) {
         $v =~ s{ [@] }{}mx; $v = to_dt $v;
      }

      $attr eq 'committee_member_id' and (length $v or $v = undef);
      $incident->$attr( $v );
   }

   if ($incident->committee_informed or $incident->committee_member_id) {
      ($incident->committee_informed and $incident->committee_member_id)
         or throw 'Must set date and member if committee informed';
   }

   $incident->controller_id( $self->$_find_person( $req->username )->id );

   return;
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
   my ($self, $req, $leg) = @_;  my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( beginning_id called collection_eta collected delivered
                     ending_id on_station operator_id )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      $attr eq 'operator_id' and not $v and next;

      if (length $v and is_member $attr,
          [ qw( called collection_eta collected delivered on_station ) ]) {
         $v =~ s{ [@] }{}mx; $v = to_dt $v;
      }

      $leg->$attr( $v );
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
sub add_incident_party_action : Role(controller) {
   my ($self, $req) = @_;

   my $iid = $req->uri_params->( 0 );
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $parties = $req->body_params->( 'people', { multiple => TRUE } );
   my $incident_party_rs = $self->schema->resultset( 'IncidentParty' );

   for my $scode (@{ $parties }) {
      my $person = $self->$_find_person( $scode );

      $incident_party_rs->create( {
         incident_party_id => $person->id, incident_id => $iid } );

      my $message = "action:add-incident_party incident_id:${iid} "
                  . "shortcode:${scode}";

      $self->send_event( $req, $message );
   }

   my $who = $req->session->user_label;
   my $message = [ to_msg '[_1] incident incident_party added by [_2]',
                   $incident->title, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub create_customer_action : Role(controller) {
   my ($self, $req) = @_;

   my $name     = $req->body_params->( 'name' );
   my $rs       = $self->schema->resultset( 'Customer' );
   my $cid      = $rs->create( { name => $name } )->id;
   my $who      = $req->session->user_label;
   my $message  = [ to_msg 'Customer [_1] created by [_2]', $cid, $who ];
   my $location = uri_for_action $req, $self->moniker.'/customers';

   return { redirect => { location => $location, message => $message } };
}

sub create_delivery_request_action : Role(controller) {
   my ($self, $req) = @_;

   my $schema   = $self->schema;
   my $cid      = $req->body_params->( 'customer_id' );
   my $customer = $schema->resultset( 'Customer' )->find( $cid );
   my $journey  = $schema->resultset( 'Journey' )->new_result( {} );
   my $c_name   = $customer->name;

   $self->$_update_journey_from_request( $req, $journey );

   try   { $journey->insert }
   catch { $self->rethrow_exception
              ( $_, 'create', 'delivery request', $c_name ) };

   my $jid = $journey->id; $c_name =~ s{ [ ] }{_}gmx; $c_name = lc $c_name;

   my $message  = "action:create-delivery delivery_id:${jid} "
                . "customer:${c_name}";

   $self->send_event( $req, $message );

   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];

   $message = [ to_msg 'Delivery request [_1] for [_2] created by [_3]',
                $jid, $customer->name, $req->session->user_label ];

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

   my $who      = $req->session->user_label;
   my $message  = [ to_msg
                    'Stage [_1] of delivery request [_2] created by [_3]',
                    $leg->id, $jid, $who ];
   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];

   return { redirect => { location => $location, message => $message } };
}

sub create_incident_action : Role(controller) {
   my ($self, $req) = @_;

   my $incident = $self->schema->resultset( 'Incident' )->new_result( {} );

   $self->$_update_incident_from_request( $req, $incident );

   my $title = $incident->title;

   try   { $incident->insert }
   catch { $self->rethrow_exception( $_, 'create', 'incident', $title ) };

   my $iid = $incident->id; $title =~ s{ [ ] }{_}gmx; $title = lc $title;
   my $message = "action:create-incident incident_id:${iid} "
               . "incident_title:${title}";

   $self->send_event( $req, $message );

   my $who = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/incident', [ $iid ];

   $message = [ to_msg 'Incident [_1] created by [_2]', $iid, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub create_location_action : Role(controller) {
   my ($self, $req) = @_;

   my $address  = $req->body_params->( 'address' );
   my $rs       = $self->schema->resultset( 'Location' );
   my $lid      = $rs->create( { address => $address } )->id;
   my $who      = $req->session->user_label;
   my $message  = [ to_msg 'Location [_1] created by [_2]', $lid, $who ];
   my $location = uri_for_action $req, $self->moniker.'/locations';

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

   $message = [ to_msg
      'Package type [_1] for delivery request [_2] created by [_3]',
                $type, $journey_id, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
};

sub customer : Role(controller) {
   my ($self, $req) = @_;

   my $cid     =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/customer', [ $cid ];
   my $form    =  blank_form 'customer', $href;
   my $action  =  $cid ? 'update' : 'create';
   my $page    =  {
      first_field => 'name',
      forms    => [ $form ],
      selected => 'customers',
      title    => locm $req, 'customer_setup_title'
   };
   my $custer  =  $self->$_maybe_find( 'Customer', $cid );

   p_fields $form, $self->schema, 'Customer', $custer,
      $self->$_bind_customer_fields( $custer, {} );

   p_action $form, $action, [ 'customer', $cid ], { request => $req };

   $cid and p_action $form, 'delete', [ 'customer', $cid ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub customers : Role(controller) {
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

   my $jid      = $req->uri_params->( 0 );
   my $journey  = $self->schema->resultset( 'Journey' )->find( $jid );
   my $c_name   = $journey->customer->name;

   $journey->delete;

   $c_name =~ s{ [ ] }{_}gmx; $c_name = lc $c_name;

   my $message = "action:delete-delivery delivery_id:${jid} customer:${c_name}";

   $self->send_event( $req, $message );

   my $who      = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/journeys';

   $message = [ to_msg 'Delivery request [_1] deleted by [_2]', $jid, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_delivery_stage_action : Role(controller) {
   my ($self, $req) = @_;

   my $jid      = $req->uri_params->( 0 );
   my $lid      = $req->uri_params->( 1 );
   my $leg      = $self->schema->resultset( 'Leg' )->find( $lid ); $leg->delete;
   my $who      = $req->session->user_label;
   my $message  = [ to_msg
                    'Stage [_1] of delivery request [_2] deleted by [_3]',
                    $lid, $jid, $who ];
   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_incident_action : Role(controller) {
   my ($self, $req) = @_;

   my $iid      = $req->uri_params->( 0 );
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $title    = $incident->title;

   $incident->delete; $title =~ s{ [ ] }{_}gmx; $title = lc $title;

   my $message  = "action:delete-incident incident_id:${iid} "
                . "incident_title:${title}";

   $self->send_event( $req, $message );

   my $who      = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/incidents';

   $message = [ to_msg 'Incident [_1] deleted by [_2]', $iid, $who ];

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

   $message = [ to_msg
      'Package type [_1] for delivery request [_2] deleted by [_3]',
                $package_type, $journey_id, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub incident : Role(controller) {
   my ($self, $req) = @_;

   my $iid = $req->uri_params->( 0, { optional => TRUE } );
   my $href = uri_for_action $req, $self->moniker.'/incident', [ $iid ];
   my $action = $iid ? 'update' : 'create';
   my $form = blank_form 'incident', $href;
   my $page = {
      forms => [ $form ], selected => 'incidents',
      title => locm $req, 'incident_title',
   };
   my $links = $self->$_incident_ops_links( $req, $iid );
   my $incident = $self->$_maybe_find( 'Incident', $iid );
   my $fopts = { disabled => FALSE };

   $iid and p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_fields $form, $self->schema, 'Incident', $incident,
      $self->$_bind_incident_fields( $page, $incident, $fopts );

   p_action $form, $action, [ 'incident', $iid ], { request => $req };

   $iid and p_action $form, 'delete', [ 'incident', $iid ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub incident_party : Role(controller) {
   my ($self, $req) = @_;

   my $iid  = $req->uri_params->( 0 );
   my $href = uri_for_action $req, $self->moniker.'/incident_party', [ $iid ];
   my $form = blank_form 'incident_party', $href;
   my $page = {
      forms => [ $form ], selected => 'incidents',
      title => locm $req, 'incident_party_title'
   };
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $title = $incident->title;
   my $parties = [ map { [ $_->person->label, $_->person->shortcode ] }
                   $incident->parties->all ];
   my $people = $_subtract->( $self->$_list_all_people, $parties );
   my $links = $self->$_incident_party_ops_links( $req, $page, $iid );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_textfield $form, 'incident', $title, {
      disabled => TRUE, label => 'incident_title' };
   p_textfield $form, 'raised', $incident->raised_label, { disabled => TRUE };

   p_select $form, 'incident_party', $parties, {
      label => 'incident_party_people', multiple => TRUE, size => 5 };

   my $tip = make_tip $req, 'remove_incident_party_tip', [ 'person', $title ];

   p_button $form, 'remove_incident_party', 'remove_incident_party', {
      class => 'delete-button', container_class => 'right-last', tip => $tip };

   p_container $form, f_tag( 'hr' ), { class => 'form-separator' };

   p_select $form, 'people', $people, { multiple => TRUE, size => 5 };

   p_button $form, 'add_incident_party', 'add_incident_party', {
      class => 'save-button', container_class => 'right-last',
      tip   => make_tip $req, 'add_incident_party_tip', [ 'person', $title ] };

   return $self->get_stash( $req, $page );
}

sub incidents : Role(controller) {
   my ($self, $req) = @_;

   my $params = $req->query_params->( { optional => TRUE } );
   my $form = blank_form;
   my $page = {
      forms => [ $form ], selected => 'incidents',
      title => locm $req, 'incidents_title',
   };
   my $is_viewer = is_member 'incident_viewer', $req->session->roles;
   my $opts      =  {
      controller => $req->username,
      is_viewer  => $is_viewer,
      page       => delete $params->{page} // 1,
      rows       => $req->session->rows_per_page,
   };
   my $rs = $self->schema->resultset( 'Incident' );
   my $incidents = $rs->search_for_incidents( $opts );
   my $links = $self->$_incidents_ops_links
      ( $req, $page, $params, $incidents->pager );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, { headers => $_incidents_headers->( $req ) };

   p_row $table, [ map { $self->$_incidents_row( $req, $_ ) }
                   $incidents->all ];

   return $self->get_stash( $req, $page );
}

sub journey : Role(controller) {
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
   my $disabled = $_is_disabled->( $req, $journey, $done );
   my $label    = locm( $req, 'delivery request' ).SPC.($jid // NUL);

   p_fields $jform, $self->schema, 'Journey', $journey,
      $self->$_bind_journey_fields( $req, $page, $journey, {
         disabled => $disabled, done => $done } );

   $disabled or p_action $jform, $action, [ 'delivery_request', $label ], {
      request => $req };

   my $is_call_viewer = is_member( 'call_viewer', $req->session->roles );

   (not $is_call_viewer and $disabled) or $done
      or ($jid and p_action $jform, 'delete', [ 'delivery_request', $label ], {
         request => $req } );

   $jid or return $self->get_stash( $req, $page );

   p_tag $pform, 'h5', locm $req, 'journey_package_title';

   my $links = $self->$_journey_package_ops_links( $req, $page, $jid );

   $disabled or p_list $pform, PIPE_SEP, $links, $_link_opts->();

   my $package_rs = $self->schema->resultset( 'Package' );
   my $packages = $package_rs->search( { journey_id => $jid }, {
      order_by => { -desc => 'quantity' } } );
   my $p_table = p_table $pform, {
      headers => $_journey_package_headers->( $req ) };

   p_row $p_table, [ map {
      $self->$_journey_package_row( $req, $page, $done, $jid, $_ ) }
                     $packages->all ];

   p_tag $lform, 'h5', locm $req, 'journey_leg_title';

   $links = $self->$_journey_leg_ops_links( $req, $jid );

   $disabled or p_list $lform, PIPE_SEP, $links, $_link_opts->();

   my $leg_rs  = $self->schema->resultset( 'Leg' );
   my $legs    = $leg_rs->search( { journey_id => $jid } );
   my $l_table = p_table $lform, { headers => $_journey_leg_headers->( $req ) };

   p_row $l_table, [ map { $self->$_journey_leg_row( $req, $jid, $_ ) }
                     $legs->all ];

   return $self->get_stash( $req, $page );
}

sub journeys : Role(controller) {
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

   my $table = p_table $form, { headers => $_journeys_headers->( $req ) };

   p_row $table, [ map  { $self->$_journeys_row( $req, $_ ) }
                   $journeys->all ];

   return $self->get_stash( $req, $page );
}

sub leg : Role(controller) {
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
      forms    => [ $form ],
      selected => $done ? 'completed' : 'journeys',
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

sub location : Role(controller) {
   my ($self, $req) = @_;

   my $lid     =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/location', [ $lid ];
   my $form    =  blank_form 'location', $href;
   my $action  =  $lid ? 'update' : 'create';
   my $page    =  {
      first_field => 'address',
      forms    => [ $form ],
      selected => 'location',
      title    => locm $req, 'location_setup_title'
   };
   my $where   =  $self->$_maybe_find( 'Location', $lid );

   p_fields $form, $self->schema, 'Location', $where,
      $self->$_bind_location_fields( $where, {} );

   p_action $form, $action, [ 'location', $lid ], { request => $req };

   $lid and p_action $form, 'delete', [ 'location', $lid ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub locations : Role(controller) {
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

sub remove_incident_party_action : Role(controller) {
   my ($self, $req) = @_;

   my $iid = $req->uri_params->( 0 );
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $parties = $req->body_params->( 'incident_party', { multiple => TRUE } );
   my $incident_party_rs = $self->schema->resultset( 'IncidentParty' );

   for my $scode (@{ $parties }) {
      my $person = $self->$_find_person( $scode );

      $incident_party_rs->find( $iid, $person->id )->delete;

      my $message = "action:remove-incident_party incident_id:${iid} "
                  . "shortcode:${scode}";

      $self->send_event( $req, $message );
   }

   my $who = $req->session->user_label;
   my $message = [ to_msg '[_1] incident incident_party removed by [_2]',
                   $incident->title, $who ];

   return { redirect => { location => $req->uri, message => $message } };
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

   $self->$_update_journey_from_request( $req, $journey );

   try   { $journey->update }
   catch { $self->rethrow_exception
              ( $_, 'update', 'delivery request', $c_name ) };

   $c_name =~ s{ [ ] }{_}gmx; $c_name = lc $c_name;

   my $message = "action:update-delivery delivery_id:${jid} customer:${c_name}";

   $self->send_event( $req, $message );

   $message = [ to_msg 'Delivery request [_1] for [_2] updated by [_3]',
                $jid, $c_name, $req->session->user_label ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_delivery_stage_action : Role(controller) {
   my ($self, $req) = @_;

   my $schema    = $self->schema;
   my $jid       = $req->uri_params->( 0 );
   my $lid       = $req->uri_params->( 1 );
   my $journey   = $schema->resultset( 'Journey' )->find( $jid );
   my $leg       = $schema->resultset( 'Leg' )->find( $lid );
   my $delivered = $leg->delivered;

   $self->$_update_leg_from_request( $req, $leg );

   my $completed = FALSE; not $delivered and $leg->delivered
      and $leg->ending_id == $journey->dropoff_id
      and $completed = TRUE;

   my $update = sub {
      $leg->update;
      $completed and $journey->completed( TRUE )
         and $journey->delivered( $leg->delivered ) and $journey->update;
   };

   try   { $self->schema->txn_do( $update ) }
   catch { $self->rethrow_exception( $_, 'update', 'delivery stage', $lid ) };

   if ($completed) {
      my $c_name = $journey->customer->name;

      $c_name =~ s{ [ ] }{_}gmx; $c_name = lc $c_name;

      my $message = "action:delivery-complete delivery_id:${jid} "
                  . "customer:${c_name}";

      $self->send_event( $req, $message );
   }

   my $message = [ to_msg 'Stage [_1] of delivery request [_2] updated by [_3]',
                   $lid, $jid, $req->session->user_label ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_incident_action : Role(controller) {
   my ($self, $req) = @_;

   my $iid = $req->uri_params->( 0 );
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $title = $incident->title;

   $self->$_update_incident_from_request( $req, $incident );

   try   { $incident->update }
   catch { $self->rethrow_exception( $_, 'update', 'incident', $iid ) };

   $title =~ s{ [ ] }{_}gmx; $title = lc $title;

   my $message = "action:update-incident incident_id:${iid} "
               . "incident_title:${title}";

   $self->send_event( $req, $message );

   my $who = $req->session->user_label;

   $message = [ to_msg 'Incident [_1] updated by [_2]', $iid, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_location_action : Role(controller) {
   my ($self, $req) = @_;

   my $lid = $req->uri_params->( 0 );
   my $location = $self->schema->resultset( 'Location' )->find( $lid );

   $location->address( $req->body_params->( 'address' ) ); $location->update;

   my $who = $req->session->user_label;
   my $message = [ to_msg 'Location [_1] updated by [_2]', $lid, $who ];

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

   $message = [ to_msg
      'Package type [_1] for delivery request [_2] updated by [_3]',
                $package_type, $journey_id, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
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
