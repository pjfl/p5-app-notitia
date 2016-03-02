package App::Notitia::Model::User;

use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::Util      qw( bind loc register_action_paths
                                set_element_focus );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Types      qw( ArrayRef );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Unexpected::Functions   qw( Unspecified );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'user';

has 'profile_keys' => is => 'ro', isa => ArrayRef, builder => sub {
   [ qw( address postcode email_address mobile_phone home_phone ) ] };

register_action_paths
   'user/login'           => 'user/login',
   'user/logout_action'   => 'user/logout',
   'user/change_password' => 'user/password',
   'user/profile'         => 'user/profile';

# Public methods
sub change_password : Role(anon) {
   my ($self, $req) = @_;

   my $name       =  $req->uri_params->( 0, { optional => TRUE } )
                 //  $req->username;
   my $page       =  {
      fields      => {
         again    => bind( 'again',    NUL, { class => 'reveal' } ),
         oldpass  => bind( 'oldpass',  NUL, { label => 'old_password' } ),
         password => bind( 'password', NUL, { autocomplete => 'off',
                                              class => 'reveal',
                                              label => 'new_password' } ),
         update   => bind( 'update', 'change_password', { class => 'right' } ),
         username => bind( 'username', $name ), },
      literal_js  =>
         "   behaviour.config.inputs[ 'again' ]
                = { event     : [ 'focus', 'blur' ],
                    method    : [ 'show_password', 'hide_password' ] };
             behaviour.config.inputs[ 'password' ]
                = { event     : [ 'focus', 'blur' ],
                    method    : [ 'show_password', 'hide_password' ] };",
      template    => [ 'contents', 'change-password' ],
      title       => loc( $req, 'change_password_title' ) };

   return $self->get_stash( $req, $page );
}

sub change_password_action : Role(anon) {
   my ($self, $req) = @_;

   my $params   = $req->body_params;
   my $name     = $params->( 'username' );
   my $oldpass  = $params->( 'oldpass',  { raw => TRUE } );
   my $password = $params->( 'password', { raw => TRUE } );
   my $again    = $params->( 'again',    { raw => TRUE } );
   my $person   = $self->schema->resultset( 'Person' )->find_person_by( $name );

   $password eq $again
      or throw 'Passwords do not match', rv => HTTP_EXPECTATION_FAILED;
   $person->set_password( $oldpass, $password );
   $req->session->username( $name ); $req->session->authenticated( TRUE );

   my $message = [ 'Person [_1] password changed', $name ];

   return { redirect => { location => $req->base, message => $message } };
}

sub index : Role(anon) {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout   => 'index',
      template => [ 'contents', 'splash' ],
      title    => loc( $req, 'main_index_title' ), } );
}

sub login_action : Role(anon) {
   my ($self, $req) = @_; my $message;

   my $session   = $req->session;
   my $params    = $req->body_params;
   my $name      = $params->( 'username' );
   my $password  = $params->( 'password', { raw => TRUE } );
   my $person_rs = $self->schema->resultset( 'Person' );

   $person_rs->find_person_by( $name )->authenticate( $password );
   $session->authenticated( TRUE ); $session->username( $name );
   $message = [ 'Person [_1] logged in', $name ];

   return { redirect => { location => $req->base, message => $message } };
}

sub login : Role(anon) {
   my ($self, $req) = @_;

   my $stash  = $self->dialog_stash( $req, 'login-user' );
   my $page   = $stash->{page};
   my $fields = $page->{fields};

   $fields->{password} = bind( 'password', NUL );
   $fields->{username} = bind( 'username', $req->username );
   $fields->{login   } = bind( 'login',    'login', { class => 'right' } );
   $page->{literal_js} = set_element_focus 'login-user', 'username';

   return $stash;
}

sub logout_action : Role(any) {
   my ($self, $req) = @_; my $location = $req->base; my $message;

   if ($req->authenticated) {
      $message  = [ 'Person [_1] logged out', $req->username ];
      $req->session->authenticated( FALSE );
   }
   else { $message = [ 'Person not logged in' ] }

   return { redirect => { location => $location, message => $message } };
}

sub profile : Role(any) {
   my ($self, $req) = @_;

   my $stash     = $self->dialog_stash( $req, 'profile-user' );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $req->username );
   my $page      = $stash->{page};
   my $fields    = $page->{fields};

   $fields->{address      } = bind( 'address',       $person->address );
   $fields->{email_address} = bind( 'email_address', $person->email_address );
   $fields->{home_phone   } = bind( 'home_phone',    $person->home_phone );
   $fields->{mobile_phone } = bind( 'mobile_phone',  $person->mobile_phone );
   $fields->{postcode     } = bind( 'postcode',      $person->postcode );
   $fields->{update       } = bind( 'update', 'update_profile',
                                    { class => 'right' } );
   $fields->{username     } = bind( 'username',      $person->name,
                                    { disabled => TRUE } );
   $page->{literal_js     } = set_element_focus 'profile-user', 'address';

   return $stash;
}

sub update_profile_action : Role(any) {
   my ($self, $req) = @_;

   my $name   = $req->username;
   my $params = $req->body_params;
   my $person = $self->schema->resultset( 'Person' )->find_person_by( $name );
   my $opts   = { raw => TRUE, optional => TRUE };

   $person->$_( $params->( $_, $opts ) ) for (@{ $self->profile_keys });

   $person->update; my $message = [ 'Person [_1] profile updated', $name ];

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
