package App::Notitia::Model::User;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::Util      qw( bind check_form_field loc mail_domain
                                register_action_paths set_element_focus
                                to_msg uri_for_action );
use Auth::GoogleAuth;
use Class::Usul::Functions  qw( create_token throw );
use Class::Usul::Types      qw( ArrayRef );
use Unexpected::Functions   qw( Unspecified );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);

# Public attributes
has '+moniker' => default => 'user';

has 'profile_keys' => is => 'ro', isa => ArrayRef, builder => sub {
   [ qw( address postcode email_address
         mobile_phone home_phone rows_per_page ) ] };

register_action_paths
   'user/change_password' => 'user/password',
   'user/check_field'     => 'check_field',
   'user/login'           => 'user/login',
   'user/login_action'    => 'user/login',
   'user/logout_action'   => 'user/logout',
   'user/profile'         => 'user/profile',
   'user/request_reset'   => 'user/reset',
   'user/totp_secret'     => 'user/totp-secret';

# Private functions
my $_rows_per_page = sub {
   my $selected = $_[ 0 ]->rows_per_page;

   return [ map { [ $_, $_, ($_ == $selected) ? { selected => TRUE } : {} ] }
            10, 20, 50, 100 ];
};

my $_update_session = sub {
   my ($session, $person) = @_;

   $session->authenticated( TRUE );
   $session->enable_2fa( $person->totp_secret ? TRUE : FALSE );
   $session->first_name( $person->first_name );
   $session->roles( [] );
   $session->rows_per_page( $person->rows_per_page );
   $session->user_label( $person->label );
   $session->username( $person->shortcode );
   return;
};

# Private methods
my $_create_reset_email = sub {
   my ($self, $req, $person, $password) = @_;

   my $conf    = $self->config;
   my $key     = substr create_token, 0, 32;
   my $subject = loc $req,
      to_msg 'Password reset for [_2]@[_1]', $conf->title, $person->name;
   my $href    = uri_for_action $req, $self->moniker.'/reset', [ $key ];
   my $post    = {
      attributes      => {
         charset      => $conf->encoding,
         content_type => 'text/html', },
      from            => $conf->title.'@'.mail_domain(),
      stash           => {
         app_name     => $conf->title,
         first_name   => $person->first_name,
         link         => $href,
         password     => $password,
         title        => $subject,
         username     => $person->name, },
      subject         => $subject,
      template        => 'password_email',
      to              => $person->email_address, };

   $conf->sessdir->catfile( $key )->println( $person->shortcode."/${password}");

   my $r = $self->send_email( $post );
   my ($id) = $r =~ m{ ^ OK \s+ id= (.+) $ }msx; chomp $id;

   $self->log->info( loc( $req, 'Reset password email sent - [_1]', [ $id ] ) );

   return;
};

# Public methods
sub change_password : Role(anon) {
   my ($self, $req) = @_;

   my $params     =  $req->uri_params;
   my $name       =  $params->( 0, { optional => TRUE } ) // $req->username;
   my $person     =  $name
                  ?  $self->schema->resultset( 'Person' )->find_person( $name )
                  :  FALSE;
   my $username   =  $person ? $person->name : $req->username;
   my $page       =  {
      fields      => {
         again    => bind( 'again',    NUL, {
            class => 'standard-field reveal' } ),
         oldpass  => bind( 'oldpass',  NUL, { label => 'old_password' } ),
         password => bind( 'password', NUL, { autocomplete => 'off',
            class => 'standard-field reveal',
            label => 'new_password' } ),
         update   => bind( 'update', 'change_password', {
            class => 'save-button right-last' } ),
         username => bind( 'username', $username ), },
      literal_js  =>
         [ "   behaviour.config.inputs[ 'again' ]",
           "      = { event     : [ 'focus', 'blur' ],",
           "          method    : [ 'show_password', 'hide_password' ] };",
           "   behaviour.config.inputs[ 'password' ]",
           "      = { event     : [ 'focus', 'blur' ],",
           "          method    : [ 'show_password', 'hide_password' ] };", ],
      location    => 'change_password',
      template    => [ 'contents', 'change-password' ],
      title       => loc( $req, 'change_password_title' ) };

   return $self->get_stash( $req, $page );
}

sub change_password_action : Role(anon) {
   my ($self, $req) = @_;

   my $session  = $req->session;
   my $params   = $req->body_params;
   my $name     = $params->( 'username' );
   my $oldpass  = $params->( 'oldpass',  { raw => TRUE } );
   my $password = $params->( 'password', { raw => TRUE } );
   my $again    = $params->( 'again',    { raw => TRUE } );
   my $person   = $self->schema->resultset( 'Person' )->find_person( $name );

   $password eq $again or throw 'Passwords do not match';
   $person->set_password( $oldpass, $password );
   $_update_session->( $session, $person );

   my $message  = [ to_msg '[_1] password changed', $person->label ];

   return { redirect => { location => $req->base, message => $message } };
}

sub check_field : Role(any) {
   my ($self, $req) = @_;

   return check_form_field $self->schema, $req, $self->log;
}

sub login : Role(anon) {
   my ($self, $req) = @_;

   my $page       =  {
      fields      => {},
      first_field => 'username',
      location    => 'home',
      template    => [ 'contents', 'login' ],
      title       => loc( $req, to_msg 'login_title', $self->config->title ), };
   my $fields     =  $page->{fields};

   $fields->{password} = bind 'password', NUL;
   $fields->{username} = bind 'username', NUL;
   $fields->{login   } = bind 'login', 'login',
                            { class => 'save-button right' };

   if ($req->session->enable_2fa) {
      $fields->{auth_code  } = bind 'auth_code', NUL;
      $fields->{totp_secret} = bind 'totp_secret', 'totp_secret',
                               { class => 'save-button right' };
   }

   return $self->get_stash( $req, $page );
}

sub login_action : Role(anon) {
   my ($self, $req) = @_;

   my $session   = $req->session;
   my $params    = $req->body_params;
   my $name      = $params->( 'username' );
   my $password  = $params->( 'password', { raw => TRUE } );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person( $name );

   $person->authenticate( $password ); $_update_session->( $session, $person );

   my $message   = [ to_msg '[_1] logged in', $person->label ];
   my $wanted    = $session->wanted; $req->session->wanted( NUL );

   $wanted and $wanted =~ m{ check_field }mx and $wanted = NUL;
   $wanted and $wanted =~ m{ totp_secret }mx and $wanted = NUL;

   my $location  = $wanted ? $req->uri_for( $wanted )
                           : uri_for_action $req, 'sched/month_rota';

   return { redirect => { location => $location, message => $message } };
}

sub logout_action : Role(any) {
   my ($self, $req) = @_; my $message;

   if ($req->authenticated) {
      $message = [ to_msg '[_1] logged out', $req->session->user_label ];
      $req->session->authenticated( FALSE );
      $req->session->roles( [] );
   }
   else { $message = [ 'Not logged in' ] }

   return { redirect => { location => $req->base, message => $message } };
}

sub profile : Role(any) {
   my ($self, $req) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_by_shortcode( $req->username );
   my $stash     = $self->dialog_stash( $req, 'profile-user' );
   my $page      = $stash->{page};
   my $fields    = $page->{fields};

   $page->{literal_js     } = set_element_focus 'profile-user', 'address';
   $fields->{address      } = bind 'address',       $person->address;
   $fields->{email_address} = bind 'email_address', $person->email_address;
   $fields->{enable_2fa   } = bind 'enable_2fa',    TRUE,
            { checked => $person->totp_secret ? TRUE : FALSE };
   $fields->{home_phone   } = bind 'home_phone',    $person->home_phone;
   $fields->{mobile_phone } = bind 'mobile_phone',  $person->mobile_phone;
   $fields->{postcode     } = bind 'postcode',      $person->postcode;
   $fields->{rows_per_page} = bind 'rows_per_page',
                                    $_rows_per_page->( $person ),
                                    { label => 'Rows Per Page' };
   $fields->{update       } = bind 'update', 'update_profile',
                                    { class => 'right-last' };
   $fields->{username     } = bind 'username',      $person->label,
                                    { disabled => TRUE };

   return $stash;
}

sub request_reset : Role(anon) {
   my ($self, $req) = @_;

   my $stash  = $self->dialog_stash( $req, 'request-reset' );
   my $page   = $stash->{page};
   my $fields = $page->{fields};
   my $opts   = { class => 'right' };

   $fields->{username} = bind 'username', NUL;
   $fields->{reset   } = bind 'request_reset', 'request_reset', $opts;
   $page->{literal_js} = set_element_focus 'request-reset', 'username';

   return $stash;
}

sub request_reset_action : Role(anon) {
   my ($self, $req) = @_;

   my $name     = $req->body_params->( 'username' );
   my $person   = $self->schema->resultset( 'Person' )->find_person( $name );
   my $password = substr create_token, 0, 12;

   $self->config->no_user_email
      or $self->$_create_reset_email( $req, $person, $password );

   my $message  = [ to_msg '[_1] password reset requested', $person->label ];

   return { redirect => { location => $req->base, message => $message } };
}

sub reset_password : Role(anon) {
   my ($self, $req) = @_; my ($location, $message);

   my $file = $req->uri_params->( 0 );
   my $path = $self->config->sessdir->catfile( $file );

   if ($path->exists and $path->is_file) {
      my $schema = $self->schema;
      my $token  = $path->chomp->getline; $path->unlink;
      my ($scode, $password) = split m{ / }mx, $token, 2;
      my $person = $schema->resultset( 'Person' )->find_by_shortcode( $scode );

      $person->password( $password ); $person->password_expired( TRUE );
      $person->update;
      $location = uri_for_action $req, 'user/change_password', [ $scode ];
      $message  = [ to_msg '[_1] password reset', $person->label ];
   }
   else {
      $location = $req->base;
      $message  = [ 'Key [_1] unknown password reset attempt', $file ];
   }

   return { redirect => { location => $location, message => $message } };
}

sub totp_secret : Role(anon) {
   my ($self, $req) = @_;

   my $scode       =  $req->uri_params->( 0 );
   my $person_rs   =  $self->schema->resultset( 'Person' );
   my $person      =  $person_rs->find_by_shortcode( $scode );
   my $totp_secret =  $req->session->collect_status_message( $req );
   my $title       =  $self->config->title;
   my $page        =  {
      fields       => {},
      location     => 'home',
      template     => [ 'contents', 'totp-secret' ],
      title        => loc( $req, to_msg 'totp_secret_title', $title ), };
   my $fields      =  $page->{fields};

   if ($totp_secret eq $person->totp_secret) {
      my $auth = Auth::GoogleAuth->new( {
         issuer => $title,
         key_id => $person->email_address,
         secret => $totp_secret,
      } );

      $fields->{qr_code} = bind 'qr_code', $auth->qr_code;
      $fields->{otpauth} = bind 'otpauth', $auth->otpauth;
   }

   return $self->get_stash( $req, $page );
}

sub totp_secret_action : Role(anon) {
   my ($self, $req) = @_;

   my $session   = $req->session;
   my $params    = $req->body_params;
   my $name      = $params->( 'username' );
   my $password  = $params->( 'password', { raw => TRUE } );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person( $name );

   $person->authenticate( $password );

   my $message   = [ to_msg '[_1]', $person->totp_secret ];
   my $actionp   = $self->moniker.'/totp_secret';
   my $location  = uri_for_action $req, $actionp, [ $person->shortcode ];

   return { redirect => { location => $location, message => $message } };
}

sub update_profile_action : Role(any) {
   my ($self, $req) = @_;

   my $scode  = $req->username;
   my $schema = $self->schema;
   my $person = $schema->resultset( 'Person' )->find_by_shortcode( $scode );
   my $opts   = { raw => TRUE, optional => TRUE };
   my $params = $req->body_params;

   $person->$_( $params->( $_, $opts ) ) for (@{ $self->profile_keys });

   $person->set_totp_secret( $params->( 'enable_2fa', $opts ) ? TRUE : FALSE );

   $req->session->enable_2fa( $person->totp_secret ? TRUE : FALSE );

   $person->update; $req->session->rows_per_page( $person->rows_per_page );

   my $message = [ to_msg '[_1] profile updated', $person->label ];

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
