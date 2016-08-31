package App::Notitia::Model::Call;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL PRIORITY_TYPE_ENUM PIPE_SEP TRUE );
use App::Notitia::Form      qw( blank_form f_link p_action p_fields p_link
                                p_list p_row p_table p_tag );
use App::Notitia::Util      qw( js_window_config locm register_action_paths
                                to_dt to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member );
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
   'call/customer' => 'customer',
   'call/journey'  => 'journey',
   'call/journeys' => 'journeys',
   'call/leg'      => 'leg',
   'call/location' => 'location';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'calls';
   $stash->{navigation} = $self->call_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_customer_tuple = sub {
   my ($selected, $customer) = @_;

   my $opts = { selected => $customer->id == $selected ? TRUE : FALSE };

   return [ $customer->name, $customer->id, $opts ];
};

my $_bind_customer = sub {
   my ($customers, $journey) = @_; my $selected = $journey->customer_id;

   return [ [ NUL, 0 ],
            map { $_customer_tuple->( $selected, $_ ) } $customers->all ];
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

my $_location_tuple = sub {
   my ($selected, $location) = @_;

   my $opts = { selected => $location->id == $selected ? TRUE : FALSE };

   return [ $location->address, $location->id, $opts ];
};

my $_bind_dropoff_location = sub {
   my ($locations, $journey) = @_; my $selected = $journey->dropoff_id;

   return [ [ NUL, 0 ],
            map { $_location_tuple->( $selected, $_ ) } @{ $locations } ];
};

my $_bind_pickup_location = sub {
   my ($locations, $journey) = @_; my $selected = $journey->pickup_id;

   return [ [ NUL, 0 ],
            map { $_location_tuple->( $selected, $_ ) } @{ $locations } ];
};

my $_journey_leg_headers = sub {
   my $req = shift; my $header = 'journey_leg_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 3 ];
};

my $_journeys_headers = sub {
   my $req = shift; my $header = 'journeys_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 3 ];
};

my $_journeys_row = sub {
   my ($self, $req, $journey) = @_;

   my $href = uri_for_action $req, $self->moniker.'/journey', [ $journey->id ];

   return [ { value => f_link $journey->customer, $href },
            { value => $journey->controller->label },
            { value => $journey->requested_label },
            { value => $journey->priority }, ];
};

my $_person_tuple = sub {
   my ($selected, $person) = @_;

   my $opts = { selected => $selected == $person->id ? TRUE : FALSE };

   return [ $person->label, $person->id, $opts ];
};

my $_bind_operator = sub {
   my ($leg, $opts) = @_; my $selected = $leg->operator_id;

   return [ [ NUL, 0 ],
            map { $_person_tuple->( $selected, $_ ) } $opts->{people}->all ];
};

my $_package_tuple = sub {
   my ($selected, $type) = @_;

   my $opts = { selected => $selected == $type->id ? TRUE : FALSE };

   return [ $type->name, $type->id, $opts ];
};

my $_bind_package_type = sub {
   my ($types, $journey) = @_;

   my $selected = $journey->package_type_id; my $other;

   return [ [ NUL, 0 ],
            (map  { $_package_tuple->( $selected, $_ ) }
             grep { $_->name eq 'other' and $other = $_; $_->name ne 'other' }
             $types->all), [ 'other', $other->id ] ];
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

# Private methods
my $_bind_beginning_location = sub {
   my ($self, $leg, $opts) = @_;

   my $leg_rs   = $self->schema->resultset( 'Leg' );
   my $where    = { journey_id => $opts->{journey_id} };
   my $selected =
        $leg->beginning_id ? $leg->beginning_id
      : $opts->{leg_count} ? ($leg_rs->search( $where )->all)[ -1 ]->ending_id
      :                      $opts->{journey}->pickup_id;

   return [ [ NUL, 0 ],
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

   return [ [ NUL, 0 ],
            map { $_location_tuple->( $selected, $_ ) }
               @{ $opts->{locations} } ];
};

my $_bind_journey_fields = sub {
   my ($self, $page, $journey, $opts) = @_; $opts //= {};

   my $schema    = $self->schema;
   my $disabled  = $opts->{disabled} // FALSE;
   my $type_rs   = $schema->resultset( 'Type' );
   my $types     = $type_rs->search_for_package_types;
   my $customers = $schema->resultset( 'Customer' )->search( {} );
   my $locations = [ $schema->resultset( 'Location' )->search( {} )->all ];
   my $other_type_id = $type_rs->search( {
      name => 'other', type_class => 'package', } )->first->id;

   push @{ $page->{literal_js} }, js_window_config 'package_type', 'change',
      'showIfNeeded', [ 'package_type', $other_type_id, 'package_other_field' ];

   return
      [  customer      => {
            disabled   => $journey->id ? TRUE : $disabled, type => 'select',
            value      => $_bind_customer->( $customers, $journey ) },
         controller    => $journey->id ? {
            disabled   => TRUE, value => $journey->controller->label } : FALSE,
         requested     => $journey->id ? {
            disabled   => TRUE, value => $journey->requested_label } : FALSE,
         priority      => {
            disabled   => $disabled, type => 'radio',
            value      => $_bind_priority->( $journey ) },
         pickup        => {
            disabled   => $disabled, type => 'select',
            value      => $_bind_pickup_location->( $locations, $journey ) },
         dropoff       => {
            disabled   => $disabled, type => 'select',
            value      => $_bind_dropoff_location->( $locations, $journey ) },
         package_type  => {
            class      => 'standard-field windows',
            disabled   => $disabled, id => 'package_type', type => 'select',
            value      => $_bind_package_type->( $types, $journey ) },
         package_other => {
            disabled   => $disabled,
            label_class => $journey->id && $journey->package_type eq 'other'
                        ? NUL : 'hidden',
            label_id => 'package_other_field' },
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

   return
      [  customer       => {
            disabled    => TRUE, value => $opts->{journey}->customer },
         operator       => {
            disabled    => $leg->id ? TRUE : $disabled, type => 'select',
            value       => $_bind_operator->( $leg, $opts ) },
         called         => $leg->id ? {
            disabled    => TRUE, value => $leg->called_label } : FALSE,
         beginning      => {
            disabled    => $disabled, type => 'select',
            value       =>
               $self->$_bind_beginning_location( $leg, $opts ) },
         ending         => {
            disabled    => $disabled, type => 'select',
            value       =>
               $self->$_bind_ending_location( $leg, $opts ) },
         collection_eta => {
            disabled    => $disabled, type => 'datetime',
            value       => $leg->collection_eta_label },
         collected      => $leg->id ? {
            disabled    => $disabled, type => 'datetime',
            value       => $leg->collected_label } : FALSE,
         delivered      => $leg->id ? {
            disabled    => $disabled, type => 'datetime',
            value       => $leg->delivered_label } : FALSE,
         on_station     => $leg->id ? {
            disabled    => $disabled, type => 'datetime',
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

my $_journey_leg_row = sub {
   my ($self, $req, $jid, $leg) = @_;

   my $href = uri_for_action $req, $self->moniker.'/leg', [ $jid, $leg->id ];

   return [ { value => f_link $leg->operator->label, $href },
            { value => $leg->called_label },
            { value => $leg->beginning },
            { value => $leg->ending }, ];
};

my $_journey_ops_links = sub {
   my ($self, $req, $jid) = @_; my $links = []; $jid or return $links;

   my $actionp = $self->moniker.'/leg';

   p_link $links, 'leg', uri_for_action( $req, $actionp, [ $jid ] ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_journeys_ops_links = sub {
   my ($self, $req, $page) = @_; my $links = [];

   my $actionp = $self->moniker.'/journey';

   p_link $links, 'journey', uri_for_action( $req, $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_leg_ops_links = sub {
   my ($self, $req, $page, $jid) = @_; my $links = [];

   my $actionp = $self->moniker.'/journey';

   p_link $links, 'journey', uri_for_action( $req, $actionp, [ $jid ] ), {
      action => 'view', container_class => 'table-link', request => $req };

   return $links;
};

my $_maybe_find_customer = sub {
   my ($self, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( 'Customer' )->find( $id );
};

my $_maybe_find_journey = sub {
   my ($self, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( 'Journey' )->find( $id );
};

my $_maybe_find_leg = sub {
   my ($self, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( 'Leg' )->find( $id );
};

my $_maybe_find_location = sub {
   my ($self, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( 'Location' )->find( $id );
};

my $_search_for_journeys = sub {
   my ($self, $status) = @_; my $rs = $self->schema->resultset( 'Journey' );

   my $opts = { prefetch => [ 'controller', 'customer' ] };
   my $completed = $status && $status eq 'completed' ? TRUE : FALSE;

   return $rs->search( { completed => $completed }, $opts );
};

my $_update_leg_from_request = sub {
   my ($self, $req, $leg) = @_;  my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( collection_eta collected delivered on_station )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      if (length $v and is_member $attr,
          [ qw( collection_eta collected delivered on_station ) ]) {
         $v =~ s{ [@] }{}mx; $v = to_dt $v;
      }

      $leg->$attr( $v );
   }

   my $v = $params->( 'operator', $opts ); defined $v
      and $leg->operator_id( $v );

   $v = $params->( 'beginning', $opts ); defined $v
      and $leg->beginning_id( $v );
   $v = $params->( 'ending', $opts ); defined $v
      and $leg->ending_id( $v );

   return;
};

my $_update_journey_from_request = sub {
   my ($self, $req, $journey) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( notes package_other priority )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      $journey->$attr( $v );
   }

   my $rs     = $self->schema->resultset( 'Person' );
   my $person = $rs->find_by_shortcode( $req->username );

   $journey->controller_id( $person->id );

   my $v = $params->( 'customer', $opts ); defined $v
      and $journey->customer_id( $v );

   $v = $params->( 'pickup', $opts ); defined $v
      and $journey->pickup_id( $v );
   $v = $params->( 'dropoff', $opts ); defined $v
      and $journey->dropoff_id( $v );
   $v = $params->( 'package_type', $opts ); defined $v
      and $journey->package_type_id( $v );

   return;
};

# Public methods
sub create_customer_action : Role(administrator) {
   my ($self, $req) = @_;

   my $name    = $req->body_params->( 'name' );
   my $rs      = $self->schema->resultset( 'Customer' );
   my $cid     = $rs->create( { name => $name } )->id;
   my $who     = $req->session->user_label;
   my $message = [ to_msg 'Customer [_1] created by [_2]', $cid, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub create_journey_action : Role(administrator) {
   my ($self, $req) = @_;

   my $schema   = $self->schema;
   my $cid      = $req->body_params->( 'customer' );
   my $customer = $schema->resultset( 'Customer' )->find( $cid );
   my $journey  = $schema->resultset( 'Journey' )->new_result( {} );

   $self->$_update_journey_from_request( $req, $journey );

   try   { $journey->insert }
   catch { $self->rethrow_exception( $_, 'create', 'journey', $customer->name)};

   my $jid      = $journey->id;
   my $who      = $req->session->user_label;
   my $message  = [ to_msg 'Journey [_1] for [_2] created by [_3]',
                    $jid, $customer->name, $who ];
   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];

   return { redirect => { location => $location, message => $message } };
}

sub create_leg_action : Role(administrator) {
   my ($self, $req) = @_;

   my $jid = $req->uri_params->( 0 );
   my $rs  = $self->schema->resultset( 'Leg' );
   my $leg = $rs->new_result( { journey_id => $jid } );

   $self->$_update_leg_from_request( $req, $leg );

   try   { $leg->insert }
   catch { $self->rethrow_exception( $_, 'create', 'leg', $jid ) };

   my $who      = $req->session->user_label;
   my $message  = [ to_msg 'Leg [_1] of journey [_2] created by [_3]',
                    $leg->id, $jid, $who ];
   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];

   return { redirect => { location => $location, message => $message } };
}

sub create_location_action : Role(administrator) {
   my ($self, $req) = @_;

   my $address = $req->body_params->( 'address' );
   my $rs      = $self->schema->resultset( 'Location' );
   my $lid     = $rs->create( { address => $address } )->id;
   my $who     = $req->session->user_label;
   my $message = [ to_msg 'Location [_1] created by [_2]', $lid, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub customer : Role(administrator) {
   my ($self, $req) = @_;

   my $cid     =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/customer', [ $cid ];
   my $form    =  blank_form 'customer', $href;
   my $action  =  $cid ? 'update' : 'create';
   my $page    =  {
      forms    => [ $form ],
      selected => 'customer',
      title    => locm $req, 'customer_setup_title'
   };
   my $custer  =  $self->$_maybe_find_customer( $cid );

   p_fields $form, $self->schema, 'Customer', $custer,
      $self->$_bind_customer_fields( $custer, {} );

   p_action $form, $action, [ 'customer', $cid ], { request => $req };

   $cid and p_action $form, 'delete', [ 'customer', $cid ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub delete_leg_action : Role(administrator) {
   my ($self, $req) = @_;

   my $jid      = $req->uri_params->( 0 );
   my $lid      = $req->uri_params->( 1 );
   my $leg      = $self->schema->resultset( 'Leg' )->find( $lid ); $leg->delete;
   my $who      = $req->session->user_label;
   my $message  = [ to_msg 'Leg [_1] of journey [_2] deleted by [_3]',
                    $lid, $jid, $who ];
   my $location = uri_for_action $req, $self->moniker.'/journey', [ $jid ];

   return { redirect => { location => $location, message => $message } };
}

sub journey : Role(administrator) {
   my ($self, $req) = @_;

   my $jid     =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/journey', [ $jid ];
   my $jform   =  blank_form 'journey', $href;
   my $lform   =  blank_form { class => 'wide-form' };
   my $action  =  $jid ? 'update' : 'create';
   my $journey =  $self->$_maybe_find_journey( $jid );
   my $done    =  $jid && $journey->completed ? TRUE : FALSE;
   my $page    =  {
      forms    => [ $jform, $lform ],
      selected => $done ? 'completed' : 'journeys',
      title    => locm $req, 'journey_call_title'
   };
   my $links   =  $self->$_journey_ops_links( $req, $jid );

   p_fields $jform, $self->schema, 'Journey', $journey,
      $self->$_bind_journey_fields( $page, $journey, { disabled => $done } );

   $done or p_action $jform, $action, [ 'journey', $jid ], { request => $req };

   $done or
      ($jid and
       p_action $jform, 'delete', [ 'journey', $jid ], { request => $req });

   $jid or return $self->get_stash( $req, $page );

   p_tag  $lform, 'h5', 'journey_leg_title';

   $done or p_list $lform, PIPE_SEP, $links, $_link_opts->();

   my $rs    = $self->schema->resultset( 'Leg' );
   my $legs  = $rs->search( { journey_id => $jid } );
   my $table = p_table $lform, { headers => $_journey_leg_headers->( $req ) };

   p_row $table, [ map { $self->$_journey_leg_row( $req, $jid, $_ ) }
                   $legs->all ];

   return $self->get_stash( $req, $page );
}

sub journeys : Role(administrator) {
   my ($self, $req) = @_;

   my $status  =  $req->query_params->( 'status', { optional => TRUE } );
   my $form    =  blank_form;
   my $page    =  {
      forms    => [ $form ],
      selected => $status && $status eq 'completed' ? 'completed' : 'journeys',
      title    => locm $req, 'journeys_title'
   };
   my $links   =  $self->$_journeys_ops_links( $req, $page );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $journeys = $self->$_search_for_journeys( $status );
   my $table    = p_table $form, { headers => $_journeys_headers->( $req ) };

   p_row $table, [ map { $self->$_journeys_row( $req, $_ ) } $journeys->all ];

   return $self->get_stash( $req, $page );
}

sub leg : Role(administrator) {
   my ($self, $req) = @_;

   my $jid     =  $req->uri_params->( 0 );
   my $lid     =  $req->uri_params->( 1, { optional => TRUE } );
   my $journey =  $self->$_maybe_find_journey( $jid );
   my $done    =  $jid && $journey->completed ? TRUE : FALSE;
   my $href    =  uri_for_action $req, $self->moniker.'/leg', [ $jid, $lid ];
   my $action  =  $lid ? 'update' : 'create';
   my $form    =  blank_form 'leg', $href;
   my $page    =  {
      forms    => [ $form ],
      selected => $done ? 'completed' : 'journeys',
      title    => locm $req, 'journey_leg_title'
   };
   my $links   =  $self->$_leg_ops_links( $req, $page, $jid );
   my $leg     =  $self->$_maybe_find_leg( $lid );
   my $count   =  !$lid ? $self->$_count_legs( $jid ) : undef;

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_fields $form, $self->schema, 'Leg', $leg, $self->$_bind_leg_fields( $leg, {
      disabled => $done, journey_id => $jid, leg_count => $count } );

   $done or p_action $form, $action, [ 'leg', $lid ], { request => $req };

   $done
      or ($lid
          and p_action $form, 'delete', [ 'leg', $lid ], { request => $req });

   return $self->get_stash( $req, $page );
}

sub location : Role(administrator) {
   my ($self, $req) = @_;

   my $lid     =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/location', [ $lid ];
   my $form    =  blank_form 'location', $href;
   my $action  =  $lid ? 'update' : 'create';
   my $page    =  {
      forms    => [ $form ],
      selected => 'location',
      title    => locm $req, 'location_setup_title'
   };
   my $where   =  $self->$_maybe_find_location( $lid );

   p_fields $form, $self->schema, 'Location', $where,
      $self->$_bind_location_fields( $where, {} );

   p_action $form, $action, [ 'location', $lid ], { request => $req };

   $lid and p_action $form, 'delete', [ 'location', $lid ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub update_leg_action : Role(administrator) {
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
      $completed and $journey->completed( TRUE ) and $journey->update;
   };

   try   { $self->schema->txn_do( $update ) }
   catch { $self->rethrow_exception( $_, 'update', 'leg', $jid ) };

   my $who     = $req->session->user_label;
   my $message = [ to_msg 'Leg [_1] of journey [_2] updated by [_3]',
                   $lid, $jid, $who ];

   return { redirect => { location => $req->uri, message => $message } };
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
