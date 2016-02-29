package App::Notitia::Model::Administration;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TILDE TRUE );
use App::Notitia::Util      qw( action_link_map loc uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_arrayref is_member throw );
use Class::Usul::Time       qw( str2date_time );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Scalar::Util            qw( blessed );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);

# Public attributes
has '+moniker' => default => 'admin';

# Private class attributes
my $_admin_links_cache = {};

# Private functions
my $_nav_folder = sub {
   return { depth => $_[ 2 ] // 0,
            title => loc( $_[ 0 ], $_[ 1 ].'_management_heading' ),
            type  => 'folder', };
};

my $_nav_link = sub {
   return { depth => $_[ 3 ] // 1,
            tip   => loc( $_[ 0 ], $_[ 2 ].'_tip' ),
            title => loc( $_[ 0 ], $_[ 2 ].'_link' ),
            type  => 'link',
            url   => action_link_map( $_[ 1 ] ), };
};

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} =
      [ $_nav_folder->( $req, 'events' ),
        $_nav_link->( $req, 'events', 'events_list' ),
        $_nav_link->( $req, 'event', 'event_create' ),
        $_nav_folder->( $req, 'people' ),
        $_nav_link->( $req, 'people', 'people_list' ),
        $_nav_link->( $req, 'person', 'person_create' ),
        $_nav_folder->( $req, 'vehicles' ),
        $_nav_link->( $req, 'vehicles', 'vehicles_list' ),
        $_nav_link->( $req, 'vehicle', 'vehicle_create' ), ];

   return $stash;
};

# Private functions
my $_add_role_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'add_role_tip', [ 'role', $name ] );

   return { container_class => 'right', label => 'add_role',
            tip             => $tip,    value => 'add_role' };
};

my $_bind_option = sub {
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

my $_bind = sub {
   my ($name, $v, $opts) = @_; $opts //= {};

   my $numify = $opts->{numify} // FALSE;
   my $params = { label => $name, name => $name }; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $params->{value} = $v->ymd;
   }
   elsif (is_arrayref $v) {
      $params->{value} = [ map { $_bind_option->( $_, $opts ) } @{ $v } ];
   }
   else { defined $v and $params->{value} = $numify ? 0 + $v : "${v}" }

   delete $opts->{numify}; delete $opts->{prefix};

   $params->{ $_ } = $opts->{ $_ } for (keys %{ $opts });

   return $params;
};

my $_bind_person_fields = sub {
   my $person = shift;

   return {
      active           => $_bind->( 'active', TRUE,
                                    { checked     => $person->active,
                                      nobreak     => TRUE, } ),
      address          => $_bind->( 'address',       $person->address ),
      dob              => $_bind->( 'dob',           $person->dob ),
      email_address    => $_bind->( 'email_address', $person->email_address ),
      first_name       => $_bind->( 'first_name',    $person->first_name ),
      home_phone       => $_bind->( 'home_phone',    $person->home_phone ),
      joined           => $_bind->( 'joined',        $person->joined ),
      last_name        => $_bind->( 'last_name',     $person->last_name ),
      mobile_phone     => $_bind->( 'mobile_phone',  $person->mobile_phone ),
      notes            => $_bind->( 'notes',         $person->notes,
                                    { class       => 'autosize' } ),
      password_expired => $_bind->( 'password_expired', TRUE,
                                    { checked     => $person->password_expired,
                                      container_class => 'right' } ),
      postcode         => $_bind->( 'postcode',      $person->postcode ),
      resigned         => $_bind->( 'resigned',      $person->resigned ),
      subscription     => $_bind->( 'subscription',  $person->subscription ),
      username         => $_bind->( 'username',      $person->name ),
   };
};

my $_delete_person_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'delete_tip', [ 'person', $name ] );

   return { container_class => 'right', label => 'delete',
            tip             => $tip,    value => 'delete_person' };
};

my $_people_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "people_heading_${_}" ) } } 0 .. 4 ];
};

my $_person_admin_links = sub {
   my ($req, $name) = @_;

   my $links = $_admin_links_cache->{ $name };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( person role certification endorsement ) ) {
      push @{ $links }, {
         value => { class => 'button fade',
                    hint  => loc( $req, 'Hint' ),
                    href  => uri_for_action( $req, $action, [ $name ] ),
                    name  => "${name}-${action}",
                    tip   => loc( $req, "${action}_management_tip" ),
                    type  => 'link',
                    value => loc( $req, "${action}_management_link" ), }, };
   }

   $_admin_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_remove_role_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'remove_role_tip', [ 'role', $name ] );

   return { container_class => 'right', label => 'remove_role',
            tip             => $tip,    value => 'remove_role' };
};

my $_save_person_button = sub {
   my ($req, $name) = @_; my $k = $name ? 'update' : 'create';

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, "${k}_tip", [ 'person', $name ] );

   return { container_class => 'right', label => $k,
            tip             => $tip,    value => "${k}_person" };
};

my $_select_next_of_kin_list = sub {
   return $_bind->( 'next_of_kin', [ [ NUL, NUL ], @{ $_[ 0 ] } ],
                    { numify => TRUE } );
};

my $_subtract = sub {
   return [ grep { is_arrayref $_ or not is_member $_, $_[ 1 ] } @{ $_[ 0 ] } ];
};

# Private methods
my $_create_user_email = sub {
   my ($self, $req, $person, $password) = @_;

   my $conf    = $self->config;
   my $key     = substr create_token, 0, 32;
   my $opts    = { params => [ $conf->title ], no_quote_bind_values => TRUE };
   my $from    = loc( $req, 'UserRegistration@[_1]', $opts );
   my $subject = loc( $req, 'Account activation for [_1]', $opts );
   my $post    = {
      attributes      => {
         charset      => $conf->encoding,
         content_type => 'text/html', },
      from            => $from,
      stash           => {
         app_name     => $conf->title,
         first_name   => $person->first_name,
         link         => uri_for_action( $req, 'activate', [ $key ] ),
         password     => $password,
         title        => $subject,
         username     => $person->name, },
      subject         => $subject,
      template        => 'user_email',
      to              => $person->email_address, };

   $conf->sessdir->catfile( $key )->println( $person->name );

   my $r = $self->send_email( $post );
   my ($id) = $r =~ m{ ^ OK \s+ id= (.+) $ }msx; chomp $id;

   $self->log->info( loc( $req, 'New user email sent - [_1]', [ $id ] ) );

   return;
};

my $_find_person_by = sub {
   my ($self, $name) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->search( { name => $name } )->single
      or throw 'User [_1] unknown', [ $name ], rv => HTTP_EXPECTATION_FAILED;

   return $person;
};

my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search
            ( { type => 'role' }, { columns => [ 'name' ] } )->all ];
};

my $_person_tuple = sub {
   my ($person, $opts) = @_; $opts //= {}; $opts->{selected} //= NUL;

   $opts->{selected} = $opts->{selected} eq $person ? TRUE : FALSE;

   return [ $person->label, $person, $opts ];
};

my $_list_all_people = sub {
   my ($self, $opts) = @_;

   my $people = $self->schema->resultset( 'Person' )->search
      ( {}, { columns => [ 'first_name', 'id', 'last_name', 'name' ] } );

   return [ map { $_person_tuple->( $_, $opts ) } $people->all ];

};

my $_update_person_from_request = sub {
   my ($self, $req, $person) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   $person->name( $params->( 'username' ) );

   for my $attr (qw( active address dob email_address first_name home_phone
                     joined last_name mobile_phone notes
                     password_expired postcode resigned subscription )) {
      my $v = $params->( $attr, $opts );

      not defined $v and is_member $attr, [ qw( active password_expired ) ]
          and $v = FALSE;

      defined $v or next;

      length $v and is_member $attr, [ qw( dob joined resigned subscription ) ]
         and $v = str2date_time( "${v} 00:00", 'GMT' );

      $person->$attr( $v );
   }

   my $v = $params->( 'next_of_kin', $opts );

   $v and $person->id and $v == $person->id
      and throw 'Cannot set self as next of kin', rv => HTTP_EXPECTATION_FAILED;
   $v or  undef $v; $person->next_of_kin( $v );

   return;
};

# Public methods
sub activate {
   my ($self, $req) = @_;

   my $file = $self->config->sessdir->catfile( $req->uri_params->( 0 ) );
   my $name = $file->chomp->getline; $file->unlink;

   $self->$_find_person_by( $name )->activate;

   my $location = uri_for_action( $req, 'password', [ $name ] );
   my $message  = [ 'User [_1] account activated', $name ];

   return { redirect => { location => $location, message => $message } };
}

sub add_role_action {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->$_find_person_by( $name );
   my $roles    = $req->body_params->( 'roles', { multiple => TRUE } );

   $person->add_member_to( $_ ) for (@{ $roles });

   my $location = uri_for_action( $req, 'role', [ $name ] );
   my $message  = [ 'Person [_1] role(s) added', $name ];

   return { redirect => { location => $location, message => $message } };
}

sub create_person_action {
   my ($self, $req) = @_;

   my $person = $self->schema->resultset( 'Person' )->new_result( {} );

   $self->$_update_person_from_request( $req, $person );

   my $role = $req->body_params->( 'roles' );

   $person->password( my $password = substr create_token, 0, 12 );
   $person->password_expired( TRUE );
   $person->insert;
   # TODO: This can throw which will fuck shit up. Needs a transaction
   $person->add_member_to( $role );

   $self->config->no_user_email
      or $self->$_create_user_email( $req, $person, $password );

   my $location = uri_for_action( $req, 'person', [ $person->name ] );
   my $message  = [ 'Person [_1] created', $person->name ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->$_find_person_by( $name ); $person->delete;
   my $location = uri_for_action( $req, 'people' );
   my $message  = [ 'Person [_1] deleted', $name ];

   return { redirect => { location => $location, message => $message } };
}

sub index {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout => 'index', template => [ 'contents', 'admin' ],
      title  => loc( $req, 'Administration' ) } );
}

sub person {
   my ($self, $req) = @_; my $people;

   my $name    =  $req->uri_params->( 0, { optional => TRUE } );
   my $person  =  $name ? $self->$_find_person_by( $name ) : Class::Null->new;
   my $page    =  {
      fields   => $_bind_person_fields->( $person ),
      template => [ 'contents', 'person' ],
      title    => loc( $req, 'person_management_heading' ), };
   my $fields  =  $page->{fields};

   if ($name) {
      $people = $self->$_list_all_people( { selected => $person->next_of_kin });
      $fields->{delete} = $_delete_person_button->( $req, $name );
      $fields->{roles } = $_bind->( 'roles', $person->list_roles );
   }
   else {
      $people = $self->$_list_all_people();
      $fields->{roles } = $_bind->( 'roles', $self->$_list_all_roles() );
   }

   $fields->{next_of_kin} = $_select_next_of_kin_list->( $people );
   $fields->{save       } = $_save_person_button->( $req, $name );

   return $self->get_stash( $req, $page );
}

sub people {
   my ($self, $req) = @_;

   my $page    =  {
      fields   => { headers => $_people_headers->( $req ),
                    rows    => [], },
      template => [ 'contents', 'people' ],
      title    => loc( $req, 'people_management_heading' ), };
   my $rows    =  $page->{fields}->{rows};
   my $people  =  $self->$_list_all_people();

   for my $person (@{ $people }) {
      push @{ $rows }, [ { value => $person->[ 0 ]  },
                         $_person_admin_links->( $req, $person->[ 1 ]->name ) ];
   }

   return $self->get_stash( $req, $page );
}

sub remove_role_action {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->$_find_person_by( $name );
   my $roles    = $req->body_params->( 'person_roles', { multiple => TRUE } );

   $person->delete_member_from( $_ ) for (@{ $roles });

   my $location = uri_for_action( $req, 'role', [ $name ] );
   my $message  = [ 'Person [_1] role(s) removed', $name ];

   return { redirect => { location => $location, message => $message } };
}

sub role {
   my ($self, $req) = @_;

   my $name    =  $req->uri_params->( 0 );
   my $person  =  $self->$_find_person_by( $name );
   my $page    =  {
      fields   => { username => { value => $name } },
      template => [ 'contents', 'role' ],
      title    => loc( $req, 'role_management_heading' ), };
   my $fields  =  $page->{fields};
   my $people  =  $self->$_list_all_people( { selected => $person } );

   my $person_roles = $person->list_roles;
   my $available    = $_subtract->( $self->$_list_all_roles(), $person_roles );

   $fields->{roles} = $_bind->( 'roles', $available,
                                { multiple => TRUE, size => 10 } );
   $fields->{person_roles}
      = $_bind->( 'person_roles', $person_roles,
                  { multiple => TRUE, size => 10 } );
   $fields->{add   } = $_add_role_button->( $req, $name );
   $fields->{remove} = $_remove_role_button->( $req, $name );

   return $self->get_stash( $req, $page );
}

sub vehicle {
   my ($self, $req) = @_;

   my $page = {
      fields   => {},
      template => [ 'contents', 'vehicle' ],
      title    => loc( $req, 'vehicle_management_heading' ), };

   return $self->get_stash( $req, $page );
}

sub update_person_action {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->$_find_person_by( $name );

   $self->$_update_person_from_request( $req, $person ); $person->update;

   my $message = [ 'User [_1] updated', $name ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_vehicle_action {
   my ($self, $req) = @_;

   my $params  = $req->body_params;
   my $name    = $params->( 'vrn' );
   my $message = [ 'Vehicle [_1] updated', $name ];

   return { redirect => { location => $req->uri, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Administration - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Administration;
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
