package App::Notitia::Model::User;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::Util      qw( set_element_focus );
use Class::Usul::Functions  qw( merge_attributes throw );
use Class::Usul::Types      qw( ArrayRef LoadableClass Object );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Unexpected::Functions   qw( Unspecified );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);

# Attribute constructors
my $_build_schema = sub {
   my $self = shift; my $extra = $self->config->connect_params;

   $self->schema_class->config( $self->config );

   return $self->schema_class->connect( @{ $self->get_connect_info }, $extra );
};

my $_build_schema_class = sub {
   return $_[ 0 ]->config->schema_classes->{ $_[ 0 ]->config->database };
};

# Public attributes
has '+moniker'     => default => 'user';

has 'profile_keys' => is => 'ro',   isa => ArrayRef, builder => sub {
   [ qw( address postcode email_address mobile_phone home_phone ) ] };

has 'schema'       => is => 'lazy', isa => Object,
   builder         => $_build_schema;

has 'schema_class' => is => 'lazy', isa => LoadableClass,
   builder         => $_build_schema_class;

# Private methods
my $_find_user_by_name = sub {
   my ($self, $name) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->search( { name => $name } )->single
      or throw 'User [_1] unknown', [ $name ], rv => HTTP_EXPECTATION_FAILED;

   return $person;
};

# Public methods
sub change_password { # : Role(anon)
   my ($self, $req) = @_;

   my $page    =  {
      user     => { username => $req->username },
      template => [ 'nav_panel', 'change-password' ],
      title    => $req->loc( 'Change Password' ) };

   return $self->get_stash( $req, $page );
}

sub change_password_action {
   my ($self, $req) = @_;

   my $name     = $req->username;
   my $params   = $req->body_params;
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

sub dialog { #  : Role(anon)
   my ($self, $req) = @_;

   my $params =  $req->query_params;
   my $name   =  $params->( 'name' );
   my $stash  =  $self->initialise_stash( $req ); $stash->{view} = 'json';
   my $page   =  $stash->{page} = $self->load_page( $req, {
      layout  => "${name}-user",
      meta    => { id => $params->( 'id' ), },
      user    => {}, } );

   if ($name eq 'profile') {
      if ($req->authenticated) {
         my $user = $self->$_find_user_by_name( $req->username );

         merge_attributes $page->{user}, $user, $self->profile_keys;
      }

      $page->{literal_js} = set_element_focus "${name}-user", 'address';
   }
   else { $page->{literal_js} = set_element_focus "${name}-user", 'username' }

   return $stash;
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

sub logout_action { # : Role(any)
   my ($self, $req) = @_; my ($location, $message);

   if ($req->authenticated) {
      $location = $req->base;
      $message  = [ 'User [_1] logged out', $req->username ];
      $req->session->authenticated( FALSE );
   }
   else { $location = $req->uri; $message = [ 'User not logged in' ] }

   return { redirect => { location => $location, message => $message } };
}

sub update_profile_action { # : Role(any)
   my ($self, $req) = @_;

   my $name   = $req->username;
   my $params = $req->body_params;
   my $user   = $self->$_find_user_by_name( $name );
   my $args   = { raw => TRUE, optional => TRUE };

   $user->$_( $params->( $_, $args ) ) for (@{ $self->profile_keys });

   $user->update;

   my $message = [ 'User [_1] profile updated', $name ];

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
