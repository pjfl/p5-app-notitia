package App::Notitia::Model::Administration;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TILDE TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind delete_button
                                loc register_action_paths save_button
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_arrayref is_member throw );
use Class::Usul::Time       qw( str2date_time );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);

# Public attributes
has '+moniker' => default => 'admin';

register_action_paths
   'admin/activate'     => 'user/activate',
   'admin/certification'=> 'certification',
   'admin/endorsement'  => 'endorsement',
   'admin/index'        => 'admin/index',
   'admin/people'       => 'users',
   'admin/person'       => 'user',
   'admin/role'         => 'role',
   'admin/vehicle'      => 'vehicle',
   'admin/vehicles'     => 'vehicles';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Private class attributes
my $_admin_links_cache = {};

# Private functions
my $_add_role_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'add_role_tip', [ 'role', $name ] );

   return { container_class => 'right', label => 'add_role',
            tip             => $tip,    value => 'add_role' };
};

my $_bind_person_fields = sub {
   my $person = shift;

   return {
      active           => bind( 'active', TRUE,
                                { checked     => $person->active,
                                  nobreak     => TRUE, } ),
      address          => bind( 'address',       $person->address ),
      dob              => bind( 'dob',           $person->dob ),
      email_address    => bind( 'email_address', $person->email_address ),
      first_name       => bind( 'first_name',    $person->first_name ),
      home_phone       => bind( 'home_phone',    $person->home_phone ),
      joined           => bind( 'joined',        $person->joined ),
      last_name        => bind( 'last_name',     $person->last_name ),
      mobile_phone     => bind( 'mobile_phone',  $person->mobile_phone ),
      notes            => bind( 'notes',         $person->notes,
                                { class       => 'autosize' } ),
      password_expired => bind( 'password_expired', TRUE,
                                { checked     => $person->password_expired,
                                  container_class => 'right' } ),
      postcode         => bind( 'postcode',      $person->postcode ),
      resigned         => bind( 'resigned',      $person->resigned ),
      subscription     => bind( 'subscription',  $person->subscription ),
      username         => bind( 'username',      $person->name ),
   };
};

my $_people_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "people_heading_${_}" ) } } 0 .. 4 ];
};

my $_remove_role_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'remove_role_tip', [ 'role', $name ] );

   return { container_class => 'right', label => 'remove_role',
            tip             => $tip,    value => 'remove_role' };
};

my $_select_next_of_kin_list = sub {
   return bind( 'next_of_kin', [ [ NUL, NUL ], @{ $_[ 0 ] } ],
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
   my $href    = uri_for_action( $req, $self->moniker.'/activate', [ $key ] );
   my $post    = {
      attributes      => {
         charset      => $conf->encoding,
         content_type => 'text/html', },
      from            => $from,
      stash           => {
         app_name     => $conf->title,
         first_name   => $person->first_name,
         link         => $href,
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

my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search
            ( { type => 'role' }, { columns => [ 'name' ] } )->all ];
};

my $_person_admin_links = sub {
   my ($self, $req, $name) = @_; my $links = $_admin_links_cache->{ $name };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( person role certification endorsement ) ) {
      my $href = uri_for_action( $req, $self->moniker."/${action}", [ $name ] );

      push @{ $links }, {
         value => { class => 'table-link fade',
                    hint  => loc( $req, 'Hint' ),
                    href  => $href,
                    name  => "${name}-${action}",
                    tip   => loc( $req, "${action}_management_tip" ),
                    type  => 'link',
                    value => loc( $req, "${action}_management_link" ), }, };
   }

   $_admin_links_cache->{ $name } = $links;

   return @{ $links };
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

      # No tz and 1/1/1970 is the last day in 69
      length $v and is_member $attr, [ qw( dob joined resigned subscription ) ]
         and $v = str2date_time( $v, 'GMT' );

      $person->$attr( $v );
   }

   my $v = $params->( 'next_of_kin', $opts );

   $v and $person->id and $v == $person->id
      and throw 'Cannot set self as next of kin', rv => HTTP_EXPECTATION_FAILED;
   $v or  undef $v; $person->next_of_kin( $v );

   return;
};

# Public methods
sub activate { # Role(anon)
   my ($self, $req) = @_; my ($location, $message);

   my $file = $req->uri_params->( 0 );
   my $path = $self->config->sessdir->catfile( $file );

   if ($path->exists and $path->is_file) {
      my $name = $path->chomp->getline; $path->unlink;

      $self->schema->resultset( 'Person' )->find_person_by( $name )->activate;

      $location = uri_for_action( $req, 'user/change_password', [ $name ] );
      $message  = [ 'User [_1] account activated', $name ];
   }
   else {
      $location = $req->base_uri;
      $message  = [ 'Key [_1] unknown activation attempt', $file ];
   }


   return { redirect => { location => $location, message => $message } };
}

sub add_role_action { # : Role(administrator) Role(person_manager)
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->schema->resultset( 'Person' )->find_person_by( $name );
   my $roles    = $req->body_params->( 'roles', { multiple => TRUE } );

   $person->add_member_to( $_ ) for (@{ $roles });

   my $location = uri_for_action( $req, $self->moniker.'/role', [ $name ] );
   my $message  =
      [ 'Person [_1] role(s) added by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub create_person_action { # : Role(administrator) Role(person_manager)
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

   my $action   = $self->moniker.'/person';
   my $location = uri_for_action( $req, $action, [ $person->name ] );
   my $message  =
      [ 'Person [_1] created by [_2]', $person->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action { # : Role(administrator) Role(person_manager)
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->schema->resultset( 'Person' )->find_person_by( $name );

   $person->delete;

   my $location = uri_for_action( $req, $self->moniker.'/people' );
   my $message  = [ 'Person [_1] deleted by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub index { # : Role(any)
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout => 'index', template => [ 'contents', 'admin' ],
      title  => loc( $req, 'Administration' ) } );
}

sub person { # : Role(administrator) Role(person_manager)
   my ($self, $req) = @_; my $people;

   my $person_rs =  $self->schema->resultset( 'Person' );
   my $name      =  $req->uri_params->( 0, { optional => TRUE } );
   my $person    =  $name ? $person_rs->find_person_by( $name )
                          :  Class::Null->new;
   my $page      =  {
      fields     => $_bind_person_fields->( $person ),
      template   => [ 'contents', 'person' ],
      title      => loc( $req, 'person_management_heading' ), };
   my $fields    =  $page->{fields};
   my $action    =  $self->moniker.'/person';

   if ($name) {
      $people = $person_rs->list_all_people
         ( { selected => $person->next_of_kin } );
      $fields->{user_href} = uri_for_action( $req, $action, [ $name ] );
      $fields->{delete   } = delete_button( $req, $name, 'person' );
      $fields->{roles    } = bind( 'roles', $person->list_roles );
   }
   else {
      $people = $person_rs->list_all_people();
      $fields->{roles    } = bind( 'roles', $self->$_list_all_roles() );
   }

   $fields->{next_of_kin} = $_select_next_of_kin_list->( $people );
   $fields->{save       } = save_button( $req, $name, 'person' );

   return $self->get_stash( $req, $page );
}

sub people { # : Role(any)
   my ($self, $req) = @_;

   my $page      =  {
      fields     => { headers => $_people_headers->( $req ), rows => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, 'people_management_heading' ), };
   my $rows      =  $page->{fields}->{rows};
   my $person_rs =  $self->schema->resultset( 'Person' );

   for my $person (@{ $person_rs->list_all_people() }) {
      push @{ $rows }, [ { value => $person->[ 0 ]  },
                         $self->$_person_admin_links
                         ( $req, $person->[ 1 ]->name ) ];
   }

   return $self->get_stash( $req, $page );
}

sub remove_role_action { # : Role(administrator) Role(person_manager)
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->schema->resultset( 'Person' )->find_person_by( $name );
   my $roles    = $req->body_params->( 'person_roles', { multiple => TRUE } );

   $person->delete_member_from( $_ ) for (@{ $roles });

   my $location = uri_for_action( $req, $self->moniker.'/role', [ $name ] );
   my $message  =
      [ 'Person [_1] role(s) removed by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub role { # : Role(administrator) Role(person_manager)
   my ($self, $req) = @_;

   my $name      =  $req->uri_params->( 0 );
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $person    =  $person_rs->find_person_by( $name );
   my $href      =  uri_for_action( $req, $self->moniker.'/role', [ $name ] );
   my $page      =  {
      fields     => { username => { href => $href } },
      template   => [ 'contents', 'role' ],
      title      => loc( $req, 'role_management_heading' ), };
   my $fields    =  $page->{fields};
   my $people    =  $person_rs->list_all_people( { selected => $person } );

   my $person_roles = $person->list_roles;
   my $available    = $_subtract->( $self->$_list_all_roles(), $person_roles );

   $fields->{roles}
      = bind( 'roles', $available, { multiple => TRUE, size => 10 } );
   $fields->{person_roles}
      = bind( 'person_roles', $person_roles, { multiple => TRUE, size => 10 } );
   $fields->{add   } = $_add_role_button->( $req, $name );
   $fields->{remove} = $_remove_role_button->( $req, $name );

   return $self->get_stash( $req, $page );
}

sub vehicle { # : Role(administrator) Role(vehicle_manager)
   my ($self, $req) = @_;

   my $page = {
      fields   => {},
      template => [ 'contents', 'vehicle' ],
      title    => loc( $req, 'vehicle_management_heading' ), };

   return $self->get_stash( $req, $page );
}

sub update_person_action { # : Role(administrator) Role(person_manager)
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->schema->resultset( 'Person' )->find_person_by( $name );

   $self->$_update_person_from_request( $req, $person ); $person->update;

   my $message = [ 'Person [_1] updated by [_2]', $name, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_vehicle_action { # : Role(administrator) Role(vehicle_manager)
   my ($self, $req) = @_;

   my $params  = $req->body_params;
   my $name    = $params->( 'vrn' );
   my $message = [ 'Vehicle [_1] updated by [_2]', $name, $req->username ];

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
