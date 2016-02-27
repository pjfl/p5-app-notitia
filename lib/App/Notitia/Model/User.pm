package App::Notitia::Model::User;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::Util      qw( loc set_element_focus );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Types      qw( ArrayRef );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Unexpected::Functions   qw( Unspecified );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'user';

has 'profile_keys' => is => 'ro', isa => ArrayRef, builder => sub {
   [ qw( address postcode email_address mobile_phone home_phone ) ] };

# Private functions
my $_bind_value = sub {
   my ($fields, $src, $k) = @_;

   $fields->{ $k } = { label => $k,  name => $k, value => $src->$k()  };

   return;
};

# Private methods
my $_dialog_stash = sub {
   my ($self, $req, $layout) = @_; my $stash = $self->initialise_stash( $req );

   $stash->{page} = $self->load_page( $req, {
      fields  => {}, layout  => $layout,
      meta    => { id => $req->query_params->( 'id' ), }, } );
   $stash->{view} = 'json';

   return $stash;
};

my $_find_user_by_name = sub {
   my ($self, $name) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->search( { name => $name } )->single
      or throw 'User [_1] unknown', [ $name ], level => 2,
               rv => HTTP_EXPECTATION_FAILED;

   return $person;
};

# Public methods
sub change_password { # : Role(anon)
   my ($self, $req) = @_;

   my $name          = $req->uri_params->( 0, { optional => TRUE } ) // NUL;
   my $page          =  {
      fields         => {
         again       => { class  => 'reveal',
                          label  => 'again',        name => 'again' },
         oldpass     => { label  => 'old_password', name => 'oldpass' },
         password    => { autocomplete => 'off',   class => 'reveal',
                          label  => 'new_password', name => 'password' },
         update      => { class  => 'right',       label => 'update',
                          value  => 'change_password' },
         username    => { label  => 'username',
                          name   => 'username',    value => $name } },
      literal_js     =>
         "behaviour.config.inputs[ 'again' ]
             = { event     : [ 'focus', 'blur' ],
                 method    : [ 'show_password', 'hide_password' ] };
          behaviour.config.inputs[ 'password' ]
             = { event     : [ 'focus', 'blur' ],
                 method    : [ 'show_password', 'hide_password' ] };",
      template       => [ 'contents', 'change-password' ],
      title          => loc( $req, 'change_password_title' ) };

   return $self->get_stash( $req, $page );
}

sub change_password_action {
   my ($self, $req) = @_;

   my $params   = $req->body_params;
   my $name     = $params->( 'username' );
   my $oldpass  = $params->( 'oldpass',  { raw => TRUE } );
   my $password = $params->( 'password', { raw => TRUE } );
   my $again    = $params->( 'again',    { raw => TRUE } );
   my $user     = $self->$_find_user_by_name( $name );

   $password eq $again
      or throw 'Passwords do not match', rv => HTTP_EXPECTATION_FAILED;
   $user->set_password( $oldpass, $password );
   $req->session->username( $name ); $req->session->authenticated( TRUE );

   my $message = [ 'User [_1] password changed', $name ];

   return { redirect => { location => $req->base, message => $message } };
}

sub login_action  { # : Role(anon)
   my ($self, $req) = @_; my $message;

   my $session  = $req->session;
   my $params   = $req->body_params;
   my $name     = $params->( 'username' );
   my $password = $params->( 'password', { raw => TRUE } );

   $self->$_find_user_by_name( $name )->authenticate( $password );
   $session->authenticated( TRUE ); $session->username( $name );
   $message = [ 'User [_1] logged in', $name ];

   return { redirect => { location => $req->base, message => $message } };
}

sub login_dialog { #  : Role(anon)
   my ($self, $req) = @_;

   my $stash = $self->$_dialog_stash( $req, 'login-user' );
   my $page  = $stash->{page};

   $page->{fields}->{login   } = {
      class => 'right', label => 'login', value => 'login', };
   $page->{fields}->{password} = {
      label => 'password',  name => 'password', };
   $page->{fields}->{username} = {
      label => 'username', name => 'username', value => $req->username, };
   $page->{literal_js} = set_element_focus 'login-user', 'username';

   return $stash;
}

sub logout_action { # : Role(any)
   my ($self, $req) = @_; my $location = $req->base; my $message;

   if ($req->authenticated) {
      $message  = [ 'User [_1] logged out', $req->username ];
      $req->session->authenticated( FALSE );
   }
   else { $message = [ 'User not logged in' ] }

   return { redirect => { location => $location, message => $message } };
}

sub profile_dialog { #  : Role(anon)
   my ($self, $req) = @_;

   my $stash = $self->$_dialog_stash( $req, 'profile-user' );
   my $page  = $stash->{page};

   if ($req->authenticated) {
      my $user   = $self->$_find_user_by_name( $req->username );
      my $fields = $page->{fields};

      $fields->{username} = { disabled => TRUE, label => 'username',
                              name     => 'username', value => $user->name };
      $_bind_value->( $fields, $user, 'address' );
      $_bind_value->( $fields, $user, 'postcode' );
      $_bind_value->( $fields, $user, 'email_address' );
      $_bind_value->( $fields, $user, 'mobile_phone' );
      $_bind_value->( $fields, $user, 'home_phone' );
      $fields->{update} = {
         class => 'right', label => 'update', value => 'update_profile', };
   }

   $page->{literal_js} = set_element_focus 'profile-user', 'address';

   return $stash;
}

sub update_profile_action { # : Role(any)
   my ($self, $req) = @_;

   my $name   = $req->username;
   my $params = $req->body_params;
   my $user   = $self->$_find_user_by_name( $name );
   my $args   = { raw => TRUE, optional => TRUE };

   $user->$_( $params->( $_, $args ) ) for (@{ $self->profile_keys });

   $user->update; my $message = [ 'User [_1] profile updated', $name ];

   return { redirect => { location => $req->base, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::User - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::User;
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
