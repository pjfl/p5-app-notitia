package App::Notitia::Model::Administration;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE TRUE );
use App::Notitia::Util      qw( loc );
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

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} =
      [ { depth => 0,
          tip   => loc( $req, 'person_administration_tip' ),
          title => loc( $req, 'person_administration' ),
          type  => 'link',
          url   => 'user', },
        { depth => 0,
          tip   => loc( $req, 'vehicle_administration_tip' ),
          title => loc( $req, 'vehicle_administration' ),
          type  => 'link',
          url   => 'vehicle', }, ];

   return $stash;
};

# Private functions
my $_bind_option = sub {
   my $v = shift;

   is_arrayref $v and return { label => $v->[ 0 ], value => $v->[ 1  ] };

   return { label => $v, value => $v }
};

my $_bind = sub {
   my ($name, $v, $opts) = @_;

   my $params = { label => $name, name => $name }; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $params->{value} = $v->ymd;
   }
   elsif (is_arrayref $v) {
      $params->{value} = [ map { $_bind_option->( $_ ) } @{ $v } ];
   }
   else { defined $v and $params->{value} = $v }

   $params->{ $_ } = $opts->{ $_ } for (keys %{ $opts });

   return $params;
};

my $_bind_person_fields = sub {
   my $user = shift;

   return {
      active           => $_bind->( 'active', TRUE,
                                    { checked     => $user->active,
                                      nobreak     => TRUE, } ),
      address          => $_bind->( 'address',       $user->address ),
      dob              => $_bind->( 'dob',           $user->dob ),
      email_address    => $_bind->( 'email_address', $user->email_address ),
      first_name       => $_bind->( 'first_name',    $user->first_name ),
      home_phone       => $_bind->( 'home_phone',    $user->home_phone ),
      joined           => $_bind->( 'joined',        $user->joined ),
      last_name        => $_bind->( 'last_name',     $user->last_name ),
      mobile_phone     => $_bind->( 'mobile_phone',  $user->mobile_phone ),
      next_of_kin      => $_bind->( 'next_of_kin',   $user->next_of_kin,
                                    { disabled    => TRUE } ),
      notes            => $_bind->( 'notes',         $user->notes,
                                    { class       => 'autosize' } ),
      password_expired => $_bind->( 'password_expired', TRUE,
                                    { checked     => $user->password_expired,
                                      container_class => 'right' } ),
      postcode         => $_bind->( 'postcode',      $user->postcode ),
      resigned         => $_bind->( 'resigned',      $user->resigned ),
      roles            => $_bind->( 'roles',         $user->list_roles ),
      subscription     => $_bind->( 'subscription',  $user->subscription ),
      username         => $_bind->( 'username',      $user->name ),
   };
};

my $_delete_person_button = sub {
   return { class => 'right', label => 'delete', value => 'delete_person' };
};

my $_save_person_button = sub {
   my $name = shift; my $k = $name ? 'update' : 'create';

   return { class => 'right', label => $k, value => "${k}_person" };
};

my $_select_person_list = sub {
   my $schema = shift; my $person_rs = $schema->resultset( 'Person' );

   my $names = [ [ '', '' ],
                 map { [ $_, "user/${_}" ] }
                 $person_rs->search( {}, { columns => [ 'name' ] } )->all ];

   return $_bind->( 'select_person', $names, { onchange => TRUE } );
};

my $_update_user_from_request = sub {
   my ($req, $user) = @_; my $params = $req->body_params;

   my $args = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   $user->name( $params->( 'username' ) );

   for my $attr (qw( active address dob email_address first_name home_phone
                     joined last_name mobile_phone notes password_expired
                     postcode resigned subscription )) {
      my $v = $params->( $attr, $args );

      not defined $v and is_member $attr, [ qw( active password_expired ) ]
          and $v = FALSE;

      defined $v or next;

      length $v and is_member $attr, [ qw( dob joined resigned subscription ) ]
         and $v = str2date_time( "${v} 00:00", 'GMT' );

      $user->$attr( $v );
   }

   return;
};

# Private methods
my $_create_user_email = sub {
   my ($self, $req, $user, $password) = @_;

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
         first_name   => $user->first_name,
         link         => $req->uri_for( 'user/activate', [ $key ] ),
         password     => $password,
         title        => $subject,
         username     => $user->name, },
      subject         => $subject,
      template        => 'user_email',
      to              => $user->email_address, };

   $conf->sessdir->catfile( $key )->println( $user->name );

   my $r = $self->send_email( $post );
   my ($id) = $r =~ m{ ^ OK \s+ id= (.+) $ }msx; chomp $id;

   $self->log->info( loc( $req, 'New user email sent - [_1]', [ $id ] ) );

   return;
};

my $_find_user_by_name = sub {
   my ($self, $name) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->search( { name => $name } )->single
      or throw 'User [_1] unknown', [ $name ], rv => HTTP_EXPECTATION_FAILED;

   return $person;
};

# Public methods
sub activate {
   my ($self, $req) = @_;

   my $file = $self->config->sessdir->catfile( $req->uri_params->( 0 ) );
   my $name = $file->chomp->getline; $file->unlink;

   $self->$_find_user_by_name( $name )->activate;

   my $location = $req->uri_for( "user/password/${name}" );
   my $message  = [ 'User [_1] account activated', $name ];

   return { redirect => { location => $location, message => $message } };
}

sub create_person_action {
   my ($self, $req) = @_;

   my $user = $self->schema->resultset( 'Person' )->new_result( {} );

   $_update_user_from_request->( $req, $user );

   $user->password( my $password = substr create_token, 0, 12 );
   $user->password_expired( TRUE );
   $user->insert;
   $self->$_create_user_email( $req, $user, $password );

   my $message  = [ 'User [_1] created', $user->name ];
   my $location = $req->uri_for( 'user/'.$user->name );

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0 );
   my $user = $self->$_find_user_by_name( $name );

   $user->delete; my $message = [ 'User [_1] deleted', $name ];

   my $location = $req->uri_for( 'user' );

   return { redirect => { location => $location, message => $message } };
}

sub index {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout => 'index', template => [ 'nav_panel', 'admin' ],
      title  => loc( $req, 'Administration' ) } );
}

sub person {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0, { optional => TRUE } );
   my $user    = $name ? $self->$_find_user_by_name( $name ) : Class::Null->new;
   my $page    = {
      fields   => $_bind_person_fields->( $user ),
      template => [ 'nav_panel', 'person' ],
      title    => loc( $req, 'person_administration' ), };
   my $fields  = $page->{fields};

   $name or  $fields->{select} = $_select_person_list->( $self->schema );
   $name and $fields->{delete} = $_delete_person_button->();
             $fields->{save  } = $_save_person_button->( $name );

   return $self->get_stash( $req, $page );
}

sub vehicle {
   my ($self, $req) = @_;

   my $page = {
      fields   => {},
      template => [ 'nav_panel', 'vehicle' ],
      title    => loc( $req, 'vehicle_administration' ), };

   return $self->get_stash( $req, $page );
}

sub update_person_action {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0 );
   my $user = $self->$_find_user_by_name( $name );

   $_update_user_from_request->( $req, $user ); $user->update;

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
