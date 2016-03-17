package App::Notitia::Model::Admin;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TILDE TRUE
                                TYPE_CLASS_ENUM );
use App::Notitia::Util      qw( admin_navigation_links bind create_button
                                delete_button field_options loc
                                management_button register_action_paths
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
   'admin/activate' => 'person/activate',
   'admin/index'    => 'admin/index',
   'admin/people'   => 'people',
   'admin/person'   => 'person',
   'admin/summary'  => 'person-summary',
   'admin/type'     => 'type',
   'admin/types'    => 'types';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;
   $stash->{page}->{location} //= 'admin';

   return $stash;
};

# Private class attributes
my $_people_links_cache = {};
my $_types_links_cache = {};

# Private functions
my $_make_tip = sub {
   my ($req, $k, $args) = @_; $args //= [];

   return loc( $req, 'Hint' ).SPC.TILDE.SPC.loc( $req, $k, $args );
};

my $_button = sub {
   my ($req, $action, $name, $args) = @_;

   my $tip = $_make_tip->( $req, "${action}_${name}_tip", $args );

   return { container_class => 'right-last', label => "${action}_${name}",
            tip => $tip, value => "${action}_${name}" };
};

my $_type_button = sub {
   return $_button->( $_[ 0 ], $_[ 1 ], 'type', $_[ 2 ] );
};

my $_add_type_button = sub {
   return $_type_button->( $_[ 0 ], 'add', $_[ 1 ] );
};

my $_remove_type_button = sub {
   return $_type_button->( $_[ 0 ], 'remove', $_[ 1 ] );
};

my $_assert_not_self = sub {
   my ($person, $nok) = @_; $nok or undef $nok;

   $nok and $person->id and $nok == $person->id
        and throw 'Cannot set self as next of kin',
                  level => 2, rv => HTTP_EXPECTATION_FAILED;

   return $nok
};

my $_maybe_find_person = sub {
   return $_[ 1 ] ? $_[ 0 ]->find_person_by( $_[ 1 ] ) : Class::Null->new;
};

my $_maybe_find_type = sub {
   return $_[ 2 ] ? $_[ 0 ]->find_type_by( $_[ 2 ], $_[ 1 ] )
                  : Class::Null->new;
};

my $_next_of_kin_list = sub {
   return bind 'next_of_kin', [ [ NUL, NUL ], @{ $_[ 0 ] } ], { numify => TRUE};
};

my $_people_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "people_heading_${_}" ) } } 0 .. 4 ];
};

my $_types_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "types_heading_${_}" ) } } 0 .. 2 ];
};

# Private methods
my $_add_type_create_buttons = sub {
   my ($self, $req, $type_class) = @_;

   my $actionp = $self->moniker.'/type'; my $buttons = [];

   if ($type_class) {
      my $k = "${type_class}_type"; my $opts = { args => [ $type_class ] };

      push @{ $buttons }, create_button( $req, $actionp, $k, $opts );
   }
   else {
      for my $type_class (@{ TYPE_CLASS_ENUM() }) {
         my $k = "${type_class}_type"; my $opts = { args => [ $type_class ] };

         push @{ $buttons }, create_button( $req, $actionp, $k, $opts );
      }
   }

   return { list => $buttons, separator => '|', type => 'list', };
};

my $_add_person_js = sub {
   my $self = shift; my $opts = { domain => 'schedule', form => 'Person' };

   return [ $self->check_field_server( 'first_name',    $opts ),
            $self->check_field_server( 'last_name',     $opts ),
            $self->check_field_server( 'email_address', $opts ), ];
};

my $_bind_person_fields = sub {
   my ($self, $person, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;
   my $map      = {
      active           => { checked => $person->active, disabled => $disabled,
                            nobreak => TRUE, },
      address          => { disabled => $disabled },
      dob              => { disabled => $disabled },
      email_address    => { class => 'server', disabled => $disabled },
      first_name       => { class => 'server', disabled => $disabled },
      home_phone       => { disabled => $disabled },
      joined           => { disabled => $disabled },
      last_name        => { class => 'server', disabled => $disabled },
      mobile_phone     => { disabled => $disabled },
      notes            => { class => 'autosize', disabled => $disabled },
      password_expired => { checked => $person->password_expired,
                            container_class => 'right-last',
                            disabled => $disabled },
      postcode         => { disabled => $disabled },
      resigned         => { disabled => $disabled },
      subscription     => { disabled => $disabled },
   };

   return $self->bind_fields( $person, $map, 'Person' );
};

my $_bind_type_fields = sub {
   my ($self, $type, $opts) = @_; $opts //= {};

   my $disabled  =  $opts->{disabled} // FALSE;
   my $map       =  {
      name       => { disabled => $disabled, label => 'type_name' }, };

   return $self->bind_fields( $type, $map, 'Type' );
};

my $_create_person_email = sub {
   my ($self, $req, $person, $password) = @_;

   my $conf    = $self->config;
   my $key     = substr create_token, 0, 32;
   my $opts    = { params => [ $conf->title ], no_quote_bind_values => TRUE };
   my $from    = loc $req, 'UserRegistration@[_1]', $opts;
   my $subject = loc $req, 'Account activation for [_1]', $opts;
   my $href    = uri_for_action $req, $self->moniker.'/activate', [ $key ];
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

   return [ [ NUL, NUL ], $type_rs->list_role_types->all ];
};

my $_new_username = sub {
   my ($self, $person) = @_; my $rs = $self->schema->resultset( 'Person' );

   return $rs->new_person_id( $person->first_name, $person->last_name );
};

my $_people_links = sub {
   my ($self, $req, $person) = @_; my $name = $person->[ 1 ]->name;

   my $links = $_people_links_cache->{ $name }; $links and return @{ $links };

   $links = [];

   for my $actionp ( qw( admin/person role/role
                         certs/certifications blots/endorsements ) ) {
      push @{ $links }, { value => management_button( $req, $actionp, $name ) };
   }

   $_people_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_types_links = sub {
   my ($self, $req, $type) = @_; my $name = $type->name;

   my $links = $_types_links_cache->{ $name }; $links and return @{ $links };

   $links = []; my $opts = { args => [ $type->type_class, $type->name ] };

   for my $actionp ( qw( admin/type ) ) {
      push @{ $links },
            { value => management_button( $req, $actionp, $name, $opts ) };
   }

   $_types_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_update_person_from_request = sub {
   my ($self, $req, $person) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( active address dob email_address first_name home_phone
                     joined last_name mobile_phone notes password_expired
                     postcode resigned subscription )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts );

      not defined $v and is_member $attr, [ qw( active password_expired ) ]
          and $v = FALSE;

      defined $v or next; $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      # No tz and 1/1/1970 is the last day in 69
      length $v and is_member $attr, [ qw( dob joined resigned subscription ) ]
         and $v = str2date_time $v, 'GMT';

      $person->$attr( $v );
   }

   $person->name( $params->( 'username', $opts )
                  || $self->$_new_username( $person ) );

   $person->next_of_kin
      ( $_assert_not_self->( $person, $params->( 'next_of_kin', $opts ) ) );

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

      $location = uri_for_action $req, 'user/change_password', [ $name ];
      $message  = [ 'Person [_1] account activated', $name ];
   }
   else {
      $location = $req->base_uri;
      $message  = [ 'Key [_1] unknown activation attempt', $file ];
   }

   return { redirect => { location => $location, message => $message } };
}

sub create_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $person = $self->schema->resultset( 'Person' )->new_result( {} );

   $self->$_update_person_from_request( $req, $person );

   my $role = $req->body_params->( 'roles', { optional => TRUE } );

   $person->password( my $password = substr create_token, 0, 12 );
   $person->password_expired( TRUE );

   my $coderef = sub {
      $person->insert; $role and $person->add_member_to( $role );
   };

   $self->schema->txn_do( $coderef );

   $self->config->no_user_email
      or $self->$_create_person_email( $req, $person, $password );

   my $actionp  = $self->moniker.'/person';
   my $location = uri_for_action $req, $actionp, [ $person->name ];
   my $message  =
      [ 'Person [_1] created by [_2]', $person->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->find_person_by( $name ); $person->delete;
   my $location = uri_for_action $req, $self->moniker.'/people';
   my $message  = [ 'Person [_1] deleted by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub find_person_by {
   return shift->schema->resultset( 'Person' )->find_person_by( @_ );
}

sub index : Role(any) {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      template => [ 'contents', 'admin-index' ],
      title    => loc( $req, 'admin_index_title' ) } );
}

sub person : Role(person_manager) {
   my ($self, $req) = @_; my $people;

   my $name       =  $req->uri_params->( 0, { optional => TRUE } );
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $page       =  {
      fields      => $self->$_bind_person_fields( $person ),
      first_field => 'first_name',
      literal_js  => $self->$_add_person_js(),
      template    => [ 'contents', 'person' ],
      title       => loc( $req, 'person_management_heading' ), };
   my $fields     =  $page->{fields};
   my $action     =  $self->moniker.'/person';
   my $opts       =  field_options $self->schema, 'Person', 'name',
                        { tip => $_make_tip->( $req, 'username_field_tip' ) };

   $fields->{username} = bind 'username', $person->name, $opts;

   if ($name) {
      my $opts = { fields => { selected => $person->next_of_kin } };

      $people  = $person_rs->list_all_people( $opts );
      $fields->{user_href   } = uri_for_action $req, $action, [ $name ];
      $fields->{delete      } = delete_button $req, $name, 'person';
      $fields->{primary_role} = bind 'primary_role', $person->list_roles;
   }
   else {
      $people  = $person_rs->list_all_people();
      $fields->{primary_role} = bind 'primary_role', $self->$_list_all_roles();
   }

   $fields->{next_of_kin} = $_next_of_kin_list->( $people );
   $fields->{save} = save_button $req, $name, 'person';

   return $self->get_stash( $req, $page );
}

sub people : Role(any) {
   my ($self, $req) = @_;

   my $role      =  $req->query_params->( 'role', { optional => TRUE } );
   my $page      =  {
      fields     => {
         add     => create_button( $req, $self->moniker.'/person', 'person' ),
         headers => $_people_headers->( $req ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, $role ? "${role}_list_link"
                                     : 'people_management_heading' ), };
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $rows      =  $page->{fields}->{rows};
   my $opts      =  { order_by => 'name' };
   my $people    =  $role ? $person_rs->list_people( $role, $opts )
                          : $person_rs->list_all_people( $opts );

   for my $person (@{ $people }) {
      push @{ $rows }, [ { value => $person->[ 0 ]  },
                         $self->$_people_links( $req, $person ) ];
   }

   return $self->get_stash( $req, $page );
}

sub summary : Role(administrator) Role(person_viewer) {
   my ($self, $req) = @_; my $people;

   my $name       =  $req->uri_params->( 0 );
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $opts       =  { disabled => TRUE };
   my $page       =  {
      fields      => $self->$_bind_person_fields( $person, $opts ),
      first_field => 'first_name',
      template    => [ 'contents', 'person' ],
      title       => loc( $req, 'person_summary_heading' ), };
   my $fields     =  $page->{fields};

   $opts    = field_options $self->schema, 'Person', 'name', $opts;
   $fields->{username    } = bind 'username', $person->name, $opts;
   $opts    = { fields => { selected => $person->next_of_kin } };
   $people  = $person_rs->list_all_people( $opts );
   $fields->{next_of_kin } = $_next_of_kin_list->( $people );
   $fields->{primary_role} = bind 'primary_roles', $person->list_roles;

   return $self->get_stash( $req, $page );
}

sub add_type_action : Role(administrator) {
   my ($self, $req) = @_;

   my $message = '';

   return { redirect => { location => $req->uri, message => $message } };
}

sub remove_type_action : Role(administrator) {
   my ($self, $req) = @_;

   my $message = '';

   return { redirect => { location => $req->uri, message => $message } };
}

sub type : Role(administrator) {
   my ($self, $req) = @_;

   my $type_class =  $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $name       =  $req->uri_params->( 1, { optional => TRUE } );
   my $type_rs    =  $self->schema->resultset( 'Type' );
   my $type       =  $_maybe_find_type->( $type_rs, $type_class, $name );
   my $opts       =  { disabled => $name ? TRUE : FALSE };
   my $page       =  {
      fields      => $self->$_bind_type_fields( $type, $opts ),
      first_field => 'name',
      template    => [ 'contents', 'type' ],
      title       => loc( $req, 'type_management_heading',
                          { params => [ ucfirst $type_class ],
                            no_quote_bind_values => TRUE, } ), };
   my $args       =  [ $type_class, $name ];
   my $fields     =  $page->{fields};

   if ($name) { $fields->{remove} = $_remove_type_button->( $req, $args ) }
   else { $fields->{add} = $_add_type_button->( $req, $args ) }

   return $self->get_stash( $req, $page );
}

sub types : Role(administrator) {
   my ($self, $req) = @_;

   my $type_class =  $req->query_params->( 'type_class', { optional => TRUE } );
   my $page       =  {
      fields      => {
         add      => $self->$_add_type_create_buttons( $req, $type_class ),
         headers  => $_types_headers->( $req ),
         rows     => [], },
      template    => [ 'contents', 'table' ],
      title       => loc( $req, $type_class ? "${type_class}_list_link"
                                            : 'types_management_heading' ), };
   my $type_rs    =  $self->schema->resultset( 'Type' );
   my $types      =  $type_class ? $type_rs->list_types( $type_class )
                                 : $type_rs->list_all_types;
   my $rows       =  $page->{fields}->{rows};

   for my $type ($types->all) {
      push @{ $rows }, [ { value => ucfirst $type->type_class },
                         { value => loc( $req, $type->name ) },
                         $self->$_types_links( $req, $type ) ];
   }

   return $self->get_stash( $req, $page );
}

sub update_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->find_person_by( $name );

   $self->$_update_person_from_request( $req, $person ); $person->update;

   my $message = [ 'Person [_1] updated by [_2]', $name, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Admin - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Admin;
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
