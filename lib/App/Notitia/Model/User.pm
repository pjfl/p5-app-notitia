package App::Notitia::Model::User;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::Form      qw( blank_form p_button p_checkbox p_image p_label
                                p_password p_radio p_text p_textfield );
use App::Notitia::Util      qw( check_form_field js_server_config
                                locm register_action_paths set_element_focus
                                to_msg uri_for_action );
use Class::Usul::Functions  qw( create_token throw );
use Class::Usul::Types      qw( ArrayRef );
use HTTP::Status            qw( HTTP_OK );
use Try::Tiny;
use Unexpected::Functions   qw( Unspecified );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(App::Notitia::Role::Messaging);

# Public attributes
has '+moniker' => default => 'user';

has 'profile_keys' => is => 'ro', isa => ArrayRef, builder => sub {
   [ qw( address postcode email_address
         mobile_phone home_phone rows_per_page ) ] };

register_action_paths
   'user/change_password' => 'user/password',
   'user/check_field'     => 'check-field',
   'user/show_if_needed'  => 'show-if-needed',
   'user/login'           => 'user/login',
   'user/login_action'    => 'user/login',
   'user/logout_action'   => 'user/logout',
   'user/profile'         => 'user/profile',
   'user/request_reset'   => 'user/reset',
   'user/totp_request'    => 'user/totp-request',
   'user/totp_secret'     => 'user/totp-secret';

# Private functions
my $_rows_per_page = sub {
   my $selected = $_[ 0 ]->rows_per_page;
   my $opts_t   = { container_class => 'radio-group', selected => TRUE };
   my $opts_f   = { container_class => 'radio-group', };

   return [ map { [ $_, $_, ($_ == $selected) ? $opts_t : $opts_f ] }
            10, 20, 50, 100 ];
};

my $_update_session = sub {
   my ($session, $person) = @_;

   $session->authenticated( TRUE );
   $session->enable_2fa( $person->totp_secret ? TRUE : FALSE );
   $session->first_name( $person->first_name );
   $session->roles( $person->list_roles );
   $session->rows_per_page( $person->rows_per_page );
   $session->user_label( $person->label );
   $session->username( $person->shortcode );
   return;
};

# Private methods
my $_add_change_password_js = sub {
   my ($self, $req, $page) = @_;

   push @{ $page->{literal_js} },
      "   behaviour.config.inputs[ 'again' ]",
      "      = { event     : [ 'focus', 'blur' ],",
      "          method    : [ 'show_password', 'hide_password' ] };",
      "   behaviour.config.inputs[ 'password' ]",
      "      = { event     : [ 'focus', 'blur' ],",
      "          method    : [ 'show_password', 'hide_password' ] };";

   return;
};

my $_add_login_js = sub {
   my ($self, $req, $page) = @_;

   my $uri = uri_for_action $req, $self->moniker.'/show_if_needed', [],
      { class => 'Person', test => 'totp_secret', };

   push @{ $page->{literal_js} }, js_server_config 'username', 'blur',
      'showIfNeeded', [ "${uri}", 'username', 'auth_code_label' ];

   return;
};

my $_fetch_shortcode = sub {
   my ($self, $req) = @_; my $scode = 'unknown';

   if (my $file = $req->uri_params->( 0, { optional => TRUE } )) {
      my $path = $self->config->sessdir->catfile( $file );

      if ($path->exists and $path->is_file) {
         $scode = $path->chomp->getline; $path->unlink;
      }
   }

   $scode eq 'unknown' and $req->authenticated and $scode = $req->username;

   return $scode;
};

# Public methods
sub change_password : Role(anon) {
   my ($self, $req) = @_;

   my $params     =  $req->uri_params;
   my $name       =  $params->( 0, { optional => TRUE } ) // $req->username;
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $name ? $person_rs->find_person( $name ) : FALSE;
   my $username   =  $person ? $person->name : $req->username;
   my $href       =  uri_for_action $req, $self->moniker.'/change_password';
   my $form       =  blank_form 'change-password', $href;
   my $page       =  {
      first_field => $username ? 'oldpass' : 'username',
      forms       => [ $form ],
      location    => 'change_password',
      title       => locm $req, 'change_password_title', $self->config->title };

   p_textfield $form, 'username', $username;
   p_password  $form, 'oldpass',  NUL, { label => 'old_password' };
   p_password  $form, 'password', NUL, { autocomplete => 'off',
                                         class => 'standard-field reveal',
                                         label => 'new_password' };
   p_password  $form, 'again',    NUL, { class => 'standard-field reveal' };
   p_button    $form, 'update', 'change_password',
                                       { class => 'save-button right-last' };

   $self->$_add_change_password_js( $req, $page );

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
   return check_form_field $_[ 0 ]->schema, $_[ 1 ], $_[ 0 ]->log;
}

sub login : Role(anon) {
   my ($self, $req) = @_;

   my $href       =  uri_for_action $req, $self->moniker.'/login';
   my $form       =  blank_form 'login-user', $href;
   my $page       =  {
      first_field => 'username',
      forms       => [ $form ],
      location    => 'login',
      title       => locm $req, 'login_title', $self->config->title };

   p_textfield $form, 'username',  NUL, { class => 'standard-field server' };
   p_password  $form, 'password';
   p_textfield $form, 'auth_code', NUL, { label_class => 'hidden',
                                          label_id    => 'auth_code_label', };
   p_button    $form, 'login', 'login', { class => 'save-button right-last' };

   $self->$_add_login_js( $req, $page );

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
   my $opts      = { optional => $person->totp_secret ? FALSE : TRUE };
   my $auth_code = $params->( 'auth_code', $opts );

   $person->authenticate_optional_2fa( $password, $auth_code );
   $_update_session->( $session, $person );

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
   my $stash     = $self->dialog_stash( $req );
   my $href      = uri_for_action $req, $self->moniker.'/profile';
   my $form      = $stash->{page}->{forms}->[ 0 ]
                 = blank_form 'profile-user', $href;

   $stash->{page}->{literal_js} = set_element_focus 'profile-user', 'address';

   p_textfield $form, 'username',      $person->label, { disabled => TRUE };
   p_textfield $form, 'address',       $person->address;
   p_textfield $form, 'postcode',      $person->postcode;
   p_textfield $form, 'email_address', $person->email_address;
   p_textfield $form, 'mobile_phone',  $person->mobile_phone;
   p_textfield $form, 'home_phone',    $person->home_phone;
   p_radio     $form, 'rows_per_page', $_rows_per_page->( $person ),
               { label => 'Rows Per Page' };
   p_checkbox  $form, 'enable_2fa',    TRUE,
               { checked => $person->totp_secret ? TRUE : FALSE };
   p_button    $form,  'update', 'update_profile', { class => 'right-last' };

   return $stash;
}

sub request_reset : Role(anon) {
   my ($self, $req) = @_;

   my $stash = $self->dialog_stash( $req );
   my $href  = uri_for_action $req, $self->moniker.'/reset';
   my $form  = $stash->{page}->{forms}->[ 0 ]
             = blank_form 'request-reset', $href;

   $stash->{page}->{literal_js} = set_element_focus 'request-reset', 'username';

   p_textfield $form, 'username';
   p_button    $form, 'request_reset', 'request_reset', { class => 'right' };

   return $stash;
}

sub request_reset_action : Role(anon) {
   my ($self, $req) = @_;

   my $name     = $req->body_params->( 'username' );
   my $person   = $self->schema->resultset( 'Person' )->find_person( $name );
   my $password = substr create_token, 0, 12;
   my $key      = '[_1] password reset requested ref. [_2]';
   my $job_id   = $self->create_reset_email( $req, $person, $password );
   my $message  = [ to_msg $key, $person->label, "send_message-${job_id}" ];

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

sub show_if_needed : Role(anon) {
   my ($self, $req) = @_; my $meta = { needed => TRUE };

   my $class = $req->query_params->( 'class' );
   my $test  = $req->query_params->( 'test' );
   my $v     = $req->query_params->( 'val', { raw => TRUE } );

   try {
      my $r = $self->schema->resultset( $class )->find_by_key( $v );

      $r->execute( $test ) or delete $meta->{needed};
   }
   catch { $self->log->error( $_ ) };

   return { code => HTTP_OK,
            page => { content => {}, meta => $meta },
            view => 'json' };
}

sub totp_request : Role(anon) {
   my ($self, $req) = @_;

   my $stash = $self->dialog_stash( $req );
   my $href  = uri_for_action $req, $self->moniker.'/reset';
   my $form  = $stash->{page}->{forms}->[ 0 ]
             = blank_form 'totp-request', $href;

   $stash->{page}->{literal_js} = set_element_focus 'totp-request', 'username';

   p_textfield $form, 'username';
   p_password  $form, 'password';
   p_textfield $form, 'mobile_phone';
   p_textfield $form, 'postcode';
   p_button    $form, 'totp_request', 'totp_request', { class => 'right-last' };

   return $stash;
}

sub totp_request_action : Role(anon) {
   my ($self, $req) = @_;

   my $session  = $req->session;
   my $params   = $req->body_params;
   my $name     = $params->( 'username' );
   my $password = $params->( 'password', { raw => TRUE } );
   my $mobile   = $params->( 'mobile_phone' );
   my $postcode = $params->( 'postcode' );
   my $person   = $self->schema->resultset( 'Person' )->find_person( $name );

   $person->authenticate( $password );
   $person->security_check( { mobile_phone => $mobile, postcode => $postcode });

   my $key      = '[_1] TOTP request sent ref. [_2]';
   my $job_id   = $self->create_totp_request_email( $req, $person );
   my $message  = [ to_msg $key, $person->label, "send_message-${job_id}" ];

   return { redirect => { location => $req->base, message => $message } };
}

sub totp_secret : Role(anon) {
   my ($self, $req) = @_;

   my $conf      =  $self->config;
   my $scode     =  $self->$_fetch_shortcode( $req );
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $person    =  $person_rs->find_by_shortcode( $scode );
   my $href      =  uri_for_action $req, $self->moniker.'/totp_secret';
   my $form      =  blank_form 'totp-secret', $href;
   my $page      =  {
      forms      => [ $form ],
      location   => 'totp_secret',
      title      => locm $req, 'totp_secret_title', $conf->title };

   p_textfield $form, 'username', $person->label, { disabled => TRUE };

   if ($person->totp_secret) {
      my $label = locm $req, 'totp_qr_code';
      my $auth  = $person->totp_authenticator;

      p_image $form, $label,      $auth->qr_code, { label => $label };
      p_text  $form, 'totp_auth', $auth->otpauth, { class => 'info-field' };
   }

   return $self->get_stash( $req, $page );
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
