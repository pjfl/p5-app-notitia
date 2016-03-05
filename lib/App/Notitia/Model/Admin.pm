package App::Notitia::Model::Admin;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
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
   'admin/activate' => 'person/activate',
   'admin/index'    => 'admin/index',
   'admin/people'   => 'people',
   'admin/person'   => 'person';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Private class attributes
my $_people_links_cache = {};

# Private functions
my $_list_all_people = sub {
   return $_[ 0 ]->list_all_people( { fields => { selected => $_[ 1 ] } } );
};

my $_maybe_find_person = sub {
   return $_[ 1 ] ? $_[ 0 ]->find_person_by( $_[ 1 ] ) : Class::Null->new;
};

my $_people_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "people_heading_${_}" ) } } 0 .. 4 ];
};

my $_select_next_of_kin_list = sub {
   return bind( 'next_of_kin', [ [ NUL, NUL ], @{ $_[ 0 ] } ],
                { numify => TRUE } );
};

# Private methods
my $_add_person_js = sub {
   my $self = shift; my $opts = { domain => 'schedule', form => 'Person' };

   return [ $self->check_field_server( 'first_name',    $opts ),
            $self->check_field_server( 'last_name',     $opts ),
            $self->check_field_server( 'email_address', $opts ), ];
};

my $_bind_person_fields = sub {
   my ($self, $person) = @_;

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

   return $self->bind_fields( $person, $map, 'Person' );
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

my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search
            ( { type => 'role' }, { columns => [ 'name' ] } )->all ];
};

my $_people_links = sub {
   my ($self, $req, $name) = @_; my $links = $_people_links_cache->{ $name };

   $links and return @{ $links }; $links = [];

   for my $path ( qw( admin/person role/role
                      certs/certifications blots/endorsements ) ) {
      my ($moniker, $action) = split m{ / }mx, $path, 2;
      my $href = uri_for_action( $req, $path, [ $name ] );

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

sub delete_person_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->find_person_by( $name ); $person->delete;
   my $location = uri_for_action( $req, $self->moniker.'/people' );
   my $message  = [ 'Person [_1] deleted by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub find_person_by {
   return $_[ 0 ]->schema->resultset( 'Person' )->find_person_by( $_[ 1 ] );
}

sub index : Role(any) {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout => 'index', template => [ 'contents', 'index' ],
      title  => loc( $req, 'admin_index_title' ) } );
}

sub person : Role(administrator) Role(person_manager) {
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
   my $opts       =  field_options( $self->schema, 'Person', 'name', {} );

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
   $fields->{username   } = bind( 'username', $person->name, $opts );

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

sub update_person_action : Role(administrator) Role(person_manager) {
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
