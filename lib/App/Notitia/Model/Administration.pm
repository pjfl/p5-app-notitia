package App::Notitia::Model::Administration;

use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TILDE TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind delete_button
                                field_options loc register_action_paths
                                save_button uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_arrayref is_member throw );
use Class::Usul::Time       qw( str2date_time );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);

# Public attributes
has '+moniker' => default => 'admin';

register_action_paths
   'admin/activate'       => 'user/activate',
   'admin/certification'  => 'certification',
   'admin/certifications' => 'certifications',
   'admin/endorsement'    => 'endorsement',
   'admin/index'          => 'admin/index',
   'admin/people'         => 'users',
   'admin/person'         => 'user',
   'admin/role'           => 'role',
   'admin/vehicle'        => 'vehicle',
   'admin/vehicles'       => 'vehicles';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Private class attributes
my $_cert_links_cache = {};
my $_people_links_cache = {};

# Private functions
my $_add_cert_button = sub {
   my ($req, $action, $name) = @_;

   return { class => 'fade',
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $action, [ $name ] ),
            name  => 'add_cert',
            tip   => loc( $req, 'add_cert_tip', [ 'certification', $name ] ),
            type  => 'link',
            value => loc( $req, 'add_cert' ) };
};

my $_add_role_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'add_role_tip', [ 'role', $name ] );

   return { container_class => 'right', label => 'add_role',
            tip             => $tip,    value => 'add_role' };
};

my $_bind_cert_fields = sub {
   my ($schema, $cert) = @_; my $fields = {};

   my $map      =  {
      completed => { class => 'server' },
      notes     => { class => 'autosize' },
   };

   for my $k (keys %{ $map }) {
      my $value = exists $map->{ $k }->{checked} ? TRUE : $cert->$k();
      my $opts  = field_options( $schema, 'Certification', $k, $map->{ $k } );

      $fields->{ $k } = bind( $k, $value, $opts );
   }

   return $fields;
};

my $_bind_person_fields = sub {
   my ($schema, $person) = @_; my $fields = {};

   my $map = {
      active           => { checked => $person->active, nobreak => TRUE, },
      address          => {},
      dob              => {},
      email_address    => { class => 'server' },
      first_name       => { class => 'server' },
      home_phone       => {},
      joined           => {},
      last_name        => { class => 'server' },
      mobile_phone     => {},
      notes            => { class => 'autosize' },
      password_expired => { checked => $person->password_expired,
                            container_class => 'right' },
      postcode         => {},
      resigned         => {},
      subscription     => {},
   };

   for my $k (keys %{ $map }) {
      my $value = exists $map->{ $k }->{checked} ? TRUE : $person->$k();
      my $opts  = field_options( $schema, 'Person', $k, $map->{ $k } );

      $fields->{ $k } = bind( $k, $value, $opts );
   }

   $fields->{username} = bind( 'username', $person->name,
                               field_options( $schema, 'Person', 'name', {} ) );

   return $fields;
};

my $_certs_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "certs_heading_${_}" ) } } 0 .. 1 ];
};

my $_find_cert = sub {
   return $_[ 2 ] ? $_[ 0 ]->find_cert_by( $_[ 1 ], $_[ 2 ]) : Class::Null->new;
};

my $_find_person = sub {
   return $_[ 1 ] ? $_[ 0 ]->find_person_by( $_[ 1 ] ) : Class::Null->new;
};

my $_list_all_people = sub {
   return $_[ 0 ]->list_all_people( { fields => { selected => $_[ 1 ] } } );
};

my $_people_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "people_heading_${_}" ) } } 0 .. 4 ];
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
my $_add_certification_js = sub {
   my $self = shift;
   my $opts = { domain => 'schedule', form => 'Certification' };

   return [ $self->check_field_server( 'completed', $opts ), ];
};

my $_add_person_js = sub {
   my $self = shift; my $opts = { domain => 'schedule', form => 'Person' };

   return [ $self->check_field_server( 'first_name',    $opts ),
            $self->check_field_server( 'last_name',     $opts ),
            $self->check_field_server( 'email_address', $opts ), ];
};

my $_cert_links = sub {
   my ($self, $req, $name, $type) = @_;

   my $links = $_cert_links_cache->{ $type };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( certification ) ) {
      my $path = $self->moniker."/${action}";
      my $href = uri_for_action( $req, $path, [ $name, $type ] );

      push @{ $links }, {
         value => { class => 'table-link fade',
                    hint  => loc( $req, 'Hint' ),
                    href  => $href,
                    name  => "${name}-${action}",
                    tip   => loc( $req, "${action}_management_tip" ),
                    type  => 'link',
                    value => loc( $req, "${action}_management_link" ), }, };
   }

   $_cert_links_cache->{ $type } = $links;

   return @{ $links };
};

my $_cert_tuple = sub {
   my ($req, $cert, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{selected} //= NUL;
   $opts->{selected}   = $opts->{selected} eq $cert ? TRUE : FALSE;

   return [ $cert->label( $req ), $cert, $opts ];
};

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

my $_list_all_certs = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search
            ( { type => 'certification' }, { columns => [ 'name' ] } )->all ];
};

my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search
            ( { type => 'role' }, { columns => [ 'name' ] } )->all ];
};

my $_list_certification_for = sub {
   my ($schema, $req, $name, $opts) = @_;

   my $fields = delete $opts->{fields} // {};
   my $certs  = $schema->resultset( 'Certification' )->search
      ( { 'recipient.name' => $name },
        { join     => [ 'recipient', 'type' ],
          order_by => 'type.type',
          prefetch => [ 'type' ] } );

   return [ map { $_cert_tuple->( $req, $_, $fields ) } $certs->all ];
};

my $_people_links = sub {
   my ($self, $req, $name) = @_; my $links = $_people_links_cache->{ $name };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( person role certifications endorsement ) ) {
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

   $_people_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_update_cert_from_request = sub {
   my ($self, $req, $cert) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   for my $attr (qw( completed notes )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      length $v and is_member $attr, [ qw( completed ) ]
         and $v = str2date_time( $v, 'GMT' );

      $cert->$attr( $v );
   }

   return;
};

my $_update_person_from_request = sub {
   my ($self, $req, $person) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

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

   my $name; unless ($name = $params->( 'username', { optional => TRUE } )) {
      my $rs = $self->schema->resultset( 'Person' );

      $name = $rs->new_person_id( $person->first_name, $person->last_name );
   }

   $person->name( $name ); my $nok = $params->( 'next_of_kin', $opts );

   $nok and $person->id and $nok == $person->id
        and throw 'Cannot set self as next of kin',
                  rv => HTTP_EXPECTATION_FAILED;
   $nok or  undef $nok; $person->next_of_kin( $nok );

   return;
};

# Public methods
sub activate : Role(anon) {
   my ($self, $req) = @_; my ($location, $message);

   my $file = $req->uri_params->( 0 );
   my $path = $self->config->sessdir->catfile( $file );

   if ($path->exists and $path->is_file) {
      my $name = $path->chomp->getline; $path->unlink;

      $self->find_person_by( $name )->activate;

      $location = uri_for_action( $req, 'user/change_password', [ $name ] );
      $message  = [ 'Person [_1] account activated', $name ];
   }
   else {
      $location = $req->base_uri;
      $message  = [ 'Key [_1] unknown activation attempt', $file ];
   }


   return { redirect => { location => $location, message => $message } };
}

sub add_role_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->find_person_by( $name );
   my $roles  = $req->body_params->( 'roles', { multiple => TRUE } );

   $person->add_member_to( $_ ) for (@{ $roles });

   my $location = uri_for_action( $req, $self->moniker.'/role', [ $name ] );
   my $message  =
      [ 'Person [_1] role(s) added by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub certification : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name      =  $req->uri_params->( 0 );
   my $type      =  $req->uri_params->( 1, { optional => TRUE } );
   my $cert_rs   =  $self->schema->resultset( 'Certification' );
   my $cert      =  $_find_cert->( $cert_rs, $name, $type );
   my $page      =  {
      fields     => $_bind_cert_fields->( $self->schema, $cert ),
      literal_js => $self->$_add_certification_js(),
      template   => [ 'contents', 'certification' ],
      title      => loc( $req, 'certification_management_heading' ), };
   my $fields    =  $page->{fields};

   if ($type) {
      my $opts = { disabled => TRUE };

      $fields->{cert_type } = bind( 'cert_type', loc( $req, $type ), $opts );
      $fields->{delete    } = delete_button( $req, $type, 'certification' );
   }
   else {
      $fields->{cert_types} = bind( 'cert_types', $self->$_list_all_certs() );
   }

   $fields->{save    } = save_button( $req, $type, 'certification' );
   $fields->{username} = bind( 'username', $name );

   return $self->get_stash( $req, $page );
}

sub certifications : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name    =  $req->uri_params->( 0 );
   my $page    =  {
      fields   => { headers  => $_certs_headers->( $req ),
                    rows     => [],
                    username => { name => $name }, },
      template => [ 'contents', 'table' ],
      title    => loc( $req, 'certificates_management_heading' ), };
   my $cert_rs =  $self->schema->resultset( 'Certification' );
   my $action  =  $self->moniker.'/certification';
   my $rows    =  $page->{fields}->{rows};

   for my $cert (@{ $_list_certification_for->( $self->schema, $req, $name )}) {
      push @{ $rows },
         [ { value => $cert->[ 0 ] },
           $self->$_cert_links( $req, $name, $cert->[ 1 ]->type ) ];
   }

   $page->{fields}->{add} = $_add_cert_button->( $req, $action, $name );

   return $self->get_stash( $req, $page );
}

sub create_certification_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0 );
   my $type    = $req->body_params->( 'cert_types' );
   my $cert_rs = $self->schema->resultset( 'Certification' );
   my $cert    = $cert_rs->new_result( { recipient => $name, type => $type } );

   $self->$_update_cert_from_request( $req, $cert ); $cert->insert;

   my $action   = $self->moniker.'/certifications';
   my $location = uri_for_action( $req, $action, [ $name ] );
   my $message  =
      [ 'Cert. [_1] for [_2] added by [_3]', $type, $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub create_person_action : Role(administrator) Role(person_manager) {
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

sub delete_certification_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $type     = $req->uri_params->( 1 );
   my $cert     = $self->find_cert_by( $name, $type ); $cert->delete;
   my $action   = $self->moniker.'/certifications';
   my $location = uri_for_action( $req, $action, [ $name ] );
   my $message  = [ 'Cert. [_1] for [_2] deleted by [_3]',
                    $type, $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->find_person_by( $name ); $person->delete;
   my $location = uri_for_action( $req, $self->moniker.'/people' );
   my $message  = [ 'Person [_1] deleted by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub find_cert_by {
   my $self = shift; my $rs = $self->schema->resultset( 'Certification' );

   return $rs->find_cert_by( @_ );
}

sub find_person_by {
   return $_[ 0 ]->schema->resultset( 'Person' )->find_person_by( $_[ 1 ] );
}

sub index : Role(any) {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout => 'index', template => [ 'contents', 'admin' ],
      title  => loc( $req, 'Administration' ) } );
}

sub person : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_; my $people;

   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $name       =  $req->uri_params->( 0, { optional => TRUE } );
   my $person     =  $_find_person->( $person_rs, $name );
   my $page       =  {
      fields      => $_bind_person_fields->( $self->schema, $person ),
      first_field => 'first_name',
      literal_js  => $self->$_add_person_js(),
      template    => [ 'contents', 'person' ],
      title       => loc( $req, 'person_management_heading' ), };
   my $fields     =  $page->{fields};
   my $action     =  $self->moniker.'/person';

   if ($name) {
      $people = $_list_all_people->( $person_rs, $person->next_of_kin );
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

sub people : Role(any) {
   my ($self, $req) = @_;

   my $page      =  {
      fields     => { headers => $_people_headers->( $req ), rows => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, 'people_management_heading' ), };
   my $rows      =  $page->{fields}->{rows};
   my $person_rs =  $self->schema->resultset( 'Person' );

   for my $person (@{ $person_rs->list_all_people( { order_by => 'name' } ) }) {
      push @{ $rows }, [ { value => $person->[ 0 ]  },
                         $self->$_people_links( $req, $person->[ 1 ]->name ) ];
   }

   return $self->get_stash( $req, $page );
}

sub remove_role_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->find_person_by( $name );
   my $roles  = $req->body_params->( 'person_roles', { multiple => TRUE } );

   $person->delete_member_from( $_ ) for (@{ $roles });

   my $location = uri_for_action( $req, $self->moniker.'/role', [ $name ] );
   my $message  =
      [ 'Person [_1] role(s) removed by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub role : Role(administrator) Role(person_manager) {
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

sub update_certification_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0 );
   my $type = $req->uri_params->( 1 );
   my $cert = $self->find_cert_by( $name, $type );

   $self->$_update_cert_from_request( $req, $cert ); $cert->update;

   my $message = [ 'Cert. [_1] for [_2] updated by [_3]',
                   $type, $name, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_person_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->find_person_by( $name );

   $self->$_update_person_from_request( $req, $person ); $person->update;

   my $message = [ 'Person [_1] updated by [_2]', $name, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_vehicle_action : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0 );
   my $message = [ 'Vehicle [_1] updated by [_2]', $name, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub vehicle : Role(administrator) Role(asset_manager) {
   my ($self, $req) = @_;

   my $page = {
      fields   => {},
      template => [ 'contents', 'vehicle' ],
      title    => loc( $req, 'vehicle_management_heading' ), };

   return $self->get_stash( $req, $page );
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
