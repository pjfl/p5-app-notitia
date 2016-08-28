package App::Notitia::Model::Journey;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_action p_cell p_container
                                p_fields p_hidden p_row p_select p_table );
use App::Notitia::Util      qw( js_server_config js_submit_config
                                locm make_tip register_action_paths
                                to_dt to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member );
use Class::Usul::Time       qw( time2str );
use Scalar::Util            qw( blessed );
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
my $_bind_customer_fields = sub {
   my ($self, $custer, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;

   return [ name => { disabled => $disabled, label => 'customer_name' } ];
};

my $_bind_journey_fields = sub {
   my ($self, $journey, $opts) = @_; $opts //= {};

   my $disabled    = $opts->{disabled} // FALSE;
   my $location_rs = $self->schema->resultset( 'Location' );
   my $locations   = [ $location_rs->search( {} )->all ];
   my $type_rs     = $self->schema->resultset( 'Type' );
   my $types       = $type_rs->search_for_package_types;
   my $customers   = $self->schema->resultset( 'Customer' )->search( {} );

   return
      [  priority      => {
            disabled   => $disabled, type => 'radio',
            value      => $_bind_priority->( $journey ) },
         requested     => $journey->id ? { disabled => TRUE } : FALSE,
         customer      => {
            disabled   => $disabled, type => 'select',
            value      => $_bind_customer->( $customers, $journey ) },
         pickup        => {
            disabled   => $disabled, type => 'select',
            value      => $_bind_pickup_location->( $locations, $journey ) },
         dropoff       => {
            disabled   => $disabled, type => 'select',
            value      => $_bind_dropoff_location->( $locations, $journey ) },
         package_type  => {
            disabled   => $disabled, type => 'select',
            value      => $_bind_package_type->( $types, $journey ) },
         package_other => { disabled => $disabled },
         notes         => $disabled ? FALSE : {
            class      => 'standard-field autosize', type => 'textarea' },
      ];
};

my $_bind_location_fields = sub {
   my ($self, $location, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;

   return [ address => { disabled => $disabled, label => 'location_address' } ];
};

my $_maybe_find_customer = sub {
   my ($self, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( 'Customer' )->find( $id );
};

my $_maybe_find_journey = sub {
   my ($self, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( 'Journey' )->find( $id );
};

my $_maybe_find_location = sub {
   my ($self, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( 'Location' )->find( $id );
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
   my $id      = $rs->create( { name => $name } )->id;
   my $who     = $req->session->user_label;
   my $message = [ to_msg 'Customer [_1] created by [_2]', $id, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub create_journey_action : Role(administrator) {
   my ($self, $req) = @_;

   my $schema = $self->schema;
   my $customer_id = $req->body_params->( 'customer' );
   my $customer = $schema->resultset( 'Customer' )->find( $customer_id );
   my $journey = $schema->resultset( 'Journey' )->new_result( {} );

   $self->$_update_journey_from_request( $req, $journey );

   try   { $journey->insert }
   catch { $self->rethrow_exception( $_, 'create', 'journey', $customer->name)};

   my $who     = $req->session->user_label;
   my $message = [ to_msg 'Journey [_1] for [_2] created by [_3]',
                   $journey->id, $customer->name, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub create_location_action : Role(administrator) {
   my ($self, $req) = @_;

   my $address = $req->body_params->( 'address' );
   my $rs      = $self->schema->resultset( 'Location' );
   my $id      = $rs->create( { address => $address } )->id;
   my $who     = $req->session->user_label;
   my $message = [ to_msg 'Location [_1] created by [_2]', $id, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub customer : Role(administrator) {
   my ($self, $req) = @_;

   my $id      =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/customer', [ $id ];
   my $form    =  blank_form 'customer', $href;
   my $action  =  $id ? 'update' : 'create';
   my $page    =  {
      forms    => [ $form ],
      title    => locm $req, 'customer_setup_title'
   };
   my $custer  =  $self->$_maybe_find_customer( $id );

   p_fields $form, $self->schema, 'Customer', $custer,
      $self->$_bind_customer_fields( $custer, {} );

   p_action $form, $action, [ 'customer', $id ], { request => $req };

   $id and p_action $form, 'delete', [ 'customer', $id ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub journey : Role(administrator) {
   my ($self, $req) = @_;

   my $id      =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/journey', [ $id ];
   my $form    =  blank_form 'journey', $href;
   my $action  =  $id ? 'update' : 'create';
   my $page    =  {
      forms    => [ $form ],
      title    => locm $req, 'journey_call_title'
   };
   my $journey =  $self->$_maybe_find_journey( $id );

   p_fields $form, $self->schema, 'Journey', $journey,
      $self->$_bind_journey_fields( $journey, {} );

   p_action $form, $action, [ 'journey', $id ], { request => $req };

   $id and p_action $form, 'delete', [ 'journey', $id ], { request => $req };

   return $self->get_stash( $req, $page );
}

sub location : Role(administrator) {
   my ($self, $req) = @_;

   my $id      =  $req->uri_params->( 0, { optional => TRUE } );
   my $href    =  uri_for_action $req, $self->moniker.'/location', [ $id ];
   my $form    =  blank_form 'location', $href;
   my $action  =  $id ? 'update' : 'create';
   my $page    =  {
      forms    => [ $form ],
      title    => locm $req, 'location_setup_title'
   };
   my $where   =  $self->$_maybe_find_location( $id );

   p_fields $form, $self->schema, 'Location', $where,
      $self->$_bind_location_fields( $where, {} );

   p_action $form, $action, [ 'location', $id ], { request => $req };

   $id and p_action $form, 'delete', [ 'location', $id ], { request => $req };

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Journey - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Journey;
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
