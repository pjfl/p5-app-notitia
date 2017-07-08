package App::Notitia::Model::CallUtils;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NBSP NUL PIPE_SEP SHIFT_TYPE_ENUM
                                SPC TRUE );
use App::Notitia::DOM       qw( new_container p_action p_button p_cell p_fields
                                p_item p_js p_link p_list p_row p_select
                                p_table p_tag p_textfield );
use App::Notitia::Util      qw( calculate_distance check_field_js crow2road
                                datetime_label dialog_anchor link_options
                                local_dt locm make_tip now_dt page_link_set
                                register_action_paths slot_limit_index
                                to_dt to_msg );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Time       qw( time2str );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(App::Notitia::Role::Holidays);
with    q(App::Notitia::Role::DatePicker);

# Public attributes
has '+moniker' => default => 'util';

register_action_paths
   'util/customer'  => 'customer',
   'util/customers' => 'customers',
   'util/distances' => 'distances',
   'util/location'  => 'location',
   'util/locations' => 'locations';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'calls';
   $stash->{navigation} = $self->call_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_add_customer_js = sub {
   my ($page, $name) = @_;

   my $opts = { domain => $name ? 'update' : 'insert', form => 'Customer' };

   p_js $page, check_field_js( 'name', $opts );

   return;
};

my $_add_location_js = sub {
   my ($page, $name) = @_;

   my $opts = { domain => $name ? 'update' : 'insert', form => 'Location' };

   p_js $page, check_field_js( 'address', $opts ),
               check_field_js( 'postcode', $opts );

   return;
};

my $_customers_headers = sub {
   my $req = shift; my $header = 'customers_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 0 ];
};

my $_locations_headers = sub {
   my $req = shift; my $header = 'locations_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 1 ];
};

# Private methods
my $_all_locations = sub {
   my ($self, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{order_by} //= 'address';

   return $self->schema->resultset( 'Location' )->search( {}, $opts )->all;
};

my $_bind_customer_fields = sub {
   my ($self, $custer, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;

   return [ name => { class => 'standard-field server',
                      disabled => $disabled, label => 'customer_name' } ];
};

my $_bind_location_fields = sub {
   my ($self, $location, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;

   return
      [ address     => { class    => 'standard-field server',
                         disabled => $disabled, label => 'location_address' },
        location    => { disabled => $disabled },
        postcode    => { class    => 'standard-field server',
                         disabled => $disabled },
        coordinates => { disabled => $disabled },
        ];
};

my $_calculate_distance = sub {
   my ($self, $location, $person) = @_;

   my $distance = calculate_distance $location, $person or return NUL;
   my $df = $self->config->distance_factor;

   $distance = crow2road $distance, $df->[ 0 ];

   my $time = int 0.5 + $df->[ 1 ] * $distance;

   return "${distance}mls (${time}mins)";
};

my $_customers_ops_links = sub {
   my ($self, $req) = @_; my $links = [];

   my $actionp = $self->moniker.'/customer';

   p_link $links, 'customer', $req->uri_for_action( $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_customers_row = sub {
   my ($self, $req, $customer) = @_; my $moniker = $self->moniker;

   my $href = $req->uri_for_action( "${moniker}/customer", [ $customer->id ] );
   my $cell = {}; p_link $cell, 'customer', $href, {
      request => $req, value => "${customer}" };

   return [ $cell ];
};

my $_find_rota_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] );
};

my $_distances_data = sub {
   my ($self, $name, $rota_dt) = @_;

   my $schema  = $self->schema;
   my $type_id = $self->$_find_rota_type( $name )->id;
   my $opts    = { rota_type => $type_id, on => $rota_dt };
   my $rs      = $schema->resultset( 'Slot' );
   my $data    = {};

   for my $slot ($rs->search_for_slots( $opts )->all) {
      $data->{ $slot->key } = $slot->operator;
   }

   return $data;
};

my $_distances_headers = sub {
   my ($self, $req, $data, $shift_t) = @_; my $row = [];

   my $col = 0; my $header = 'distances_heading_';

   p_item $row, locm $req, $header.$col++;

   my $limits = $self->config->slot_limits;

   for my $slot_t ('rider', 'driver') {
      my $max_slots = $limits->[ slot_limit_index $shift_t, $slot_t ];

      for my $slot_no (0 .. $max_slots - 1) {
         my $person = $data->{ "${shift_t}_${slot_t}_${slot_no}" };

         p_item $row,
            $person ? locm $req, $header.$col++, $person->label : NBSP;
      }
   }

   return $row;
};

my $_distances_ops_links = sub {
   my ($self, $req, $page, $rota_name, $rota_dt) = @_; my $links = [];

   my $href = $req->uri_for_action( $self->moniker.'/distances' );

   push @{ $links }, $self->date_picker
      ( $req, 'day-selector', $rota_name, local_dt( $rota_dt ), $href );

   $self->date_picker_js( $page );

   return $links;
};

my $_distances_row = sub {
   my ($self, $data, $shift_t, $location) = @_; my $row = [];

   p_item $row, $location;

   my $limits = $self->config->slot_limits;

   for my $slot_t ('rider', 'driver') {
      my $max_slots = $limits->[ slot_limit_index $shift_t, $slot_t ];

      for my $slot_no (0 .. $max_slots - 1) {
         if (my $person = $data->{ "${shift_t}_${slot_t}_${slot_no}" }) {
            p_item $row, $self->$_calculate_distance( $location, $person );
         }
         else { p_item $row, NUL }
      }
   }

   return $row;
};

my $_locations_ops_links = sub {
   my ($self, $req) = @_; my $links = [];

   my $actionp = $self->moniker.'/location';

   p_link $links, 'location', $req->uri_for_action( $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_locations_row = sub {
   my ($self, $req, $location) = @_; my $moniker = $self->moniker;

   my $href = $req->uri_for_action( "${moniker}/location", [ $location->id ] );
   my $cell = {}; p_link $cell, 'location', $href, {
      request => $req, value => "${location}" };

   return [ $cell, { value => $location->postcode } ];
};

my $_maybe_find = sub {
   my ($self, $class, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( $class )->find( $id );
};

my $_update_location_from_request = sub {
   my ($self, $req, $location) = @_; my $params = $req->body_params;

   for my $attr (qw( address coordinates location postcode )) {
      my $v = $params->( $attr, { optional => TRUE } );

      (defined $v and length $v) or next;
      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;
      $location->$attr( $v );
   }

   return;
};

# Public methods
sub create_customer_action : Role(call_manager) Role(controller) {
   my ($self, $req) = @_;

   my $name     = $req->body_params->( 'name' );
   my $rs       = $self->schema->resultset( 'Customer' );
   my $cid      = $rs->create( { name => $name } )->id;
   my $key      = 'Customer [_1] created by [_2]';
   my $message  = [ to_msg $key, $name, $req->session->user_label ];
   my $location = $req->uri_for_action( $self->moniker.'/customers' );

   return { redirect => { location => $location, message => $message } };
}

sub create_location_action : Role(call_manager) Role(controller) {
   my ($self, $req) = @_;

   my $address  = $req->body_params->( 'address' );
   my $rs       = $self->schema->resultset( 'Location' );
   my $location = $rs->new_result( {} );

   $self->$_update_location_from_request( $req, $location );
   $location->insert;

   my $lid = $location->id;
   my $message = "action:create-location location_id:${lid}";

   $self->send_event( $req, $message );

   my $key = 'Location [_1] created by [_2]';

   $message = [ to_msg $key, $lid, $req->session->user_label ];
   $location = $req->uri_for_action( $self->moniker.'/locations' );

   return { redirect => { location => $location, message => $message } };
}

sub customer : Role(call_manager) Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $cid     =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  $req->uri_for_action( $self->moniker.'/customer', [ $cid ] );
   my $form    =  new_container 'customer', $href;
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

   $_add_customer_js->( $page, $cid );

   return $self->get_stash( $req, $page );
}

sub customers : Role(call_manager) Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $form = new_container { class => 'standard-form' };
   my $page = {
      forms => [ $form ], selected => 'customers',
      title => locm $req, 'customers_list_title'
   };
   my $links = $self->$_customers_ops_links( $req );

   p_list $form, PIPE_SEP, $links, link_options 'right';

   my $table = p_table $form, { headers => $_customers_headers->( $req ) };
   my $customers = $self->schema->resultset( 'Customer' )->search( {} );

   p_row $table, [ map { $self->$_customers_row( $req, $_ ) } $customers->all ];

   return $self->get_stash( $req, $page );
}

sub delete_customer_action : Role(call_manager) Role(controller) {
   my ($self, $req) = @_;

   my $cid = $req->uri_params->( 0 );
   my $custer = $self->schema->resultset( 'Customer' )->find( $cid );
   my $c_name = $custer->name; $custer->delete;
   my $who = $req->session->user_label;
   my $message = [ to_msg 'Customer [_1] deleted by [_2]', $c_name, $who ];
   my $location = $req->uri_for_action( $self->moniker.'/customers' );

   return { redirect => { location => $location, message => $message } };
}

sub delete_location_action : Role(call_manager) Role(controller) {
   my ($self, $req) = @_;

   my $lid = $req->uri_params->( 0 );
   my $location = $self->schema->resultset( 'Location' )->find( $lid );
   my $address = $location->address; $location->delete;
   my $who = $req->session->user_label;
   my $message = [ to_msg 'Location [_1] deleted by [_2]', $address, $who ];

   $location = $req->uri_for_action( $self->moniker.'/locations' );

   return { redirect => { location => $location, message => $message } };
}

sub day_selector_action : Role(call_manager) Role(controller) {
   my ($self, $req) = @_;

   return $self->date_picker_redirect( $req, $self->moniker.'/distances' );
}

sub distances : Role(call_manager) Role(controller) {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $name      = $params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date = $params->( 1, { optional => TRUE } ) // time2str '%Y-%m-%d';
   my $rota_dt   = to_dt $rota_date;
   my $local_dt  = local_dt( $rota_dt );
   my $show_date = $local_dt->month_name.SPC.$local_dt->day.SPC.$local_dt->year;
   my $form      = new_container { class => 'shifts' };
   my $page      = {
      forms      => [ $form ],
      selected   => 'distances',
      title      => locm $req, 'distances_title', $show_date };
   my $data      = $self->$_distances_data( $name, $rota_dt );
   my $links     = $self->$_distances_ops_links( $req, $page, $name, $rota_dt );

   p_list $form, PIPE_SEP, $links, { class => 'label right' };

   for my $shift_t (@{ SHIFT_TYPE_ENUM() }) {
      $shift_t eq 'day' and $self->is_working_day( $local_dt ) and next;

      p_tag $form, 'h5', locm( $req, "${shift_t}_shift_subtitle" ), {
         class => 'label left' };

      my $table = p_table $form, {
         headers => $self->$_distances_headers( $req, $data, $shift_t ) };

      p_row $table, [ map { $self->$_distances_row( $data, $shift_t, $_ ) }
                      $self->$_all_locations ];
   }

   return $self->get_stash( $req, $page );
}

sub location : Role(call_manager) Role(controller) Role(driver) Role(rider) {
   my ($self, $req) = @_;

   my $lid = $req->uri_params->( 0, { optional => TRUE } );
   my $href = $req->uri_for_action( $self->moniker.'/location', [ $lid ] );
   my $form = new_container 'location', $href;
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

   my $form  = new_container { class => 'standard-form' };
   my $page  = {
      forms  => [ $form ], selected => 'locations',
      title  => locm $req, 'locations_list_title'
   };
   my $links = $self->$_locations_ops_links( $req );

   p_list $form, PIPE_SEP, $links, link_options 'right';

   my $table = p_table $form, { headers => $_locations_headers->( $req ) };

   p_row $table, [ map { $self->$_locations_row( $req, $_ ) }
                   $self->$_all_locations ];

   return $self->get_stash( $req, $page );
}

sub update_customer_action : Role(call_manager) Role(controller) {
   my ($self, $req) = @_;

   my $cid = $req->uri_params->( 0 );
   my $custer = $self->schema->resultset( 'Customer' )->find( $cid );
   my $c_name = $custer->name( $req->body_params->( 'name' ) ); $custer->update;
   my $who = $req->session->user_label;
   my $message = [ to_msg 'Customer [_1] updated by [_2]', $c_name, $who ];
   my $location = $req->uri_for_action( $self->moniker.'/customers' );

   return { redirect => { location => $location, message => $message } };
}

sub update_location_action : Role(call_manager) Role(controller) {
   my ($self, $req) = @_;

   my $lid = $req->uri_params->( 0 );
   my $location = $self->schema->resultset( 'Location' )->find( $lid );

   $self->$_update_location_from_request( $req, $location );
   $location->update;

   my $message = "action:update-location location_id:${lid}";

   $self->send_event( $req, $message );

   my $key = 'Location [_1] updated by [_2]';

   $message = [ to_msg $key, $location->address, $req->session->user_label ];
   $location = $req->uri_for_action( $self->moniker.'/locations' );

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::CallUtils - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::CallUtils;
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
