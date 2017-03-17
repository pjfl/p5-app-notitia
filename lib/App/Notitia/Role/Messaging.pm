package App::Notitia::Role::Messaging;

use namespace::autoclean;

use App::Notitia::Form      qw( blank_form p_button p_js p_link
                                p_radio p_select p_textarea );
use App::Notitia::Constants qw( C_DIALOG EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::Util      qw( js_togglers_config js_window_config locm
                                mail_domain set_element_focus to_msg );
use Class::Usul::File;
use Class::Usul::Functions  qw( create_token throw trim );
use Moo::Role;

requires qw( config create_email_job dialog_stash moniker schema );

# Private functions
my $_contains_one = sub {
   my ($params, $keys) = @_;

   for my $key (@{ $keys }) { exists $params->{ $key } and return TRUE }

   return FALSE;
};

my $_plate_label = sub {
   my $v = ucfirst $_[ 0 ]->basename( '.md' ); $v =~ s{[_\-]}{ }gmx; return $v;
};

# Private methods
my $_session_file = sub {
   return $_[ 0 ]->config->sessdir->catfile( substr create_token, 0, 32 );
};

my $_flatten = sub {
   my ($self, $req) = @_; my $r = NUL;

   my $selected = $req->body_params->( 'selected', {
      optional => TRUE, multiple => TRUE } );
   my $params = $req->query_params->( {
      optional => TRUE } ) // {}; delete $params->{mid};

   if (defined $selected->[ 0 ]) {
      my $path = $self->$_session_file;
      my $opts = { data => { selected => $selected },
                   path => $path->assert, storage_class => 'JSON' };

      Class::Usul::File->data_dump( $opts ); $r = "-o recipients=${path} ";
   }
   else {
      scalar keys %{ $params } or throw 'Messaging all people is not allowed';

      $_contains_one->( $params, [ qw( stash event role ) ] )
         or throw 'Must select a sub-set of people to message';

      exists $params->{type} and $params->{type} eq 'contacts'
         and throw 'Messaging all contacts is not allowed';

      for my $k (keys %{ $params }) { $r .= "-o ${k}=".$params->{ $k }.' ' }
   }

   return $r;
};

my $_make_template = sub {
   my ($self, $message) = @_;

   my $path = $self->$_session_file; $path->println( trim $message );

   return $path;
};

my $_template_dir = sub {
   my ($self, $req) = @_; my $conf = $self->config; my $root = $conf->docs_root;

   return $root->catdir( $req->locale, $conf->posts, $conf->email_templates );
};

my $_template_path = sub {
   my ($self, $name) = @_; my $conf = $self->config;

   my $file = $conf->template_dir->catfile( "custom/${name}.tt" );

   $file->exists and return $file;

   return $conf->template_dir->catfile( $conf->skin."/${name}.tt" );
};

my $_list_message_templates = sub {
   my ($self, $req) = @_; my $dir = $self->$_template_dir( $req );

   $dir->exists or return [ [ NUL, NUL ] ];

   my $plates = $dir->filter( sub { m{ \.md \z }mx } );

   return [ map { [ $_plate_label->( $_ ), "${_}" ] } $plates->all_files ];
};

# Public methods
sub create_person_email {
   my ($self, $req, $person, $password) = @_;

   my $conf     = $self->config;
   my $scode    = $person->shortcode;
   my $token    = substr create_token, 0, 32;
   my $key      = 'Account activation for [_2]@[_1]';
   my $template = $self->$_template_path( 'user_email' );
   my $subject  = locm $req, $key, $conf->title, $person->name;
   my $link     = $req->uri_for_action( $self->moniker.'/activate', [ $token ]);
   my $stash    = { app_name => $conf->title, link => $link,
                    password => $password, shortcode => $scode,
                    subject  => $subject, };

   $conf->sessdir->catfile( $token )->println( $scode );

   return $self->create_email_job( $stash, $template );
}

sub create_reset_email {
   my ($self, $req, $person, $password) = @_;

   my $conf     = $self->config;
   my $scode    = $person->shortcode;
   my $token    = substr create_token, 0, 32;
   my $key      = 'Password reset for [_2]@[_1]';
   my $template = $self->$_template_path( 'password_email' );
   my $subject  = locm $req, $key, $conf->title, $person->name;
   my $link     = $req->uri_for_action( $self->moniker.'/reset', [ $token ] );
   my $stash    = { app_name => $conf->title, link => $link,
                    password => $password, shortcode => $scode,
                    subject  => $subject, };

   $conf->sessdir->catfile( $token )->println( "${scode}/${password}" );

   return $self->create_email_job( $stash, $template );
}

sub create_totp_request_email {
   my ($self, $req, $person) = @_;

   my $conf     = $self->config;
   my $key      = 'TOTP Request for [_2]@[_1]';
   my $template = $self->$_template_path( 'totp_request_email' );
   my $subject  = locm $req, $key, $conf->title, $person->name;
   my $token    = substr create_token, 0, 32;
   my $actionp  = $self->moniker.'/totp_secret';
   my $link     = $req->uri_for_action( $actionp, [ $token ] );
   my $scode    = $person->shortcode;
   my $stash    = { app_name => $conf->title, link => $link,
                    shortcode => $scode, subject => $subject, };

   $conf->sessdir->catfile( $token )->println( $scode );

   return $self->create_email_job( $stash, $template );
}

sub message_create {
   my ($self, $req, $opts) = @_;

   my $conf = $self->config;
   my $sink = $req->body_params->( 'sink' );
   my $template;

   if ($sink eq 'adhoc_email') {
      my $message = $req->body_params->( 'email_message', { raw => TRUE } );

      $message =~ s{ \r\n }{\n}gmx;
      $template = $self->$_make_template( $message ); $sink = 'email';
   }
   elsif ($sink eq 'template_email') {
      $template = $req->body_params->( 'template' ); $sink = 'email';
   }
   elsif ($sink eq 'sms') {
      my $message = $req->body_params->( 'sms_message' );

      $template = $self->$_make_template( $message );
   }
   else { throw 'Sink [_1] unknown', [ $sink ] }

   my $cmd      = $conf->binsdir->catfile( 'notitia-util' ).SPC
                . $self->$_flatten( $req )."send_message ${sink} ${template}";
   my $job_rs   = $self->schema->resultset( 'Job' );
   my $job      = $job_rs->create( { command => $cmd, name => 'send_message' });
   my $location = $req->uri_for_action( $self->moniker.'/'.$opts->{action} );
   my $message  = [ to_msg 'Job [_1] created by [_2]',
                           $job->label, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub message_link {
   my ($self, $req, $page, $href, $name, $links) = @_;

   my $args   =  [ "${href}", {
      name    => $name,
      target  => $page->{forms}->[ 0 ]->{form_name} // $page->{form}->{name},
      title   => locm( $req, 'message_title' ),
      useIcon => \1 } ];

   p_js $page, js_window_config 'send_message', 'click', 'inlineDialog', $args;

   p_link $links, 'message', C_DIALOG, { action => 'send', request => $req };
   return;
}

sub message_stash {
   my ($self, $req) = @_;

   my $id = substr create_token, 0, 5;
   my $stash = $self->dialog_stash( $req );
   my $form = $stash->{page}->{forms}->[ 0 ]
            = blank_form NUL, { class => 'standard-form' };
   my $templates = $self->$_list_message_templates( $req );
   my $plate_eml_id = "template_email_${id}";
   my $adhoc_eml_id = "adhoc_email_${id}";
   my $sms_id = "sms_${id}";
   my $sink_vals =
      [ [ 'Adhoc Email', 'adhoc_email', {
           class => 'togglers', id => $adhoc_eml_id, selected => TRUE } ],
        [ 'Template Email', 'template_email', {
           class => 'togglers', id => $plate_eml_id } ],
        [ 'SMS', 'sms', { class => 'togglers', id => $sms_id } ] ];
   my $subject = locm $req, '[_1] Notification', $self->config->title;
   my $email_val = "---\nsubject: ${subject}\n---\n\n\n";

   p_radio $form, 'sink', $sink_vals, { label => 'Message sink' };

   p_select $form, 'template', [ [ NUL, NUL ], @{ $templates } ], {
      label_id => "${plate_eml_id}_label", label_class => 'hidden' };

   p_textarea $form, 'email_message', $email_val, {
      class    => 'standard-field clear autosize',
      id       => "${adhoc_eml_id}_message",
      label_id => "${adhoc_eml_id}_label" };

   p_textarea $form, 'sms_message', "\n\n", {
      id       => "${sms_id}_message",
      class    => 'standard-field clear autosize', label_class => 'hidden',
      label_id => "${sms_id}_label" };

   p_button $form, 'confirm', 'message_create', { class => 'button right-last'};

   $stash->{page}->{literal_js} = set_element_focus "people", 'email_message';

   p_js $stash->{page}, js_togglers_config $plate_eml_id, 'checked',
      'showSelected', [ $plate_eml_id, "${plate_eml_id}_label" ];

   p_js $stash->{page}, js_togglers_config  $adhoc_eml_id, 'checked',
      'showSelected', [ $adhoc_eml_id, "${adhoc_eml_id}_label" ];

   p_js $stash->{page}, js_togglers_config  $sms_id, 'checked',
      'showSelected', [ $sms_id, "${sms_id}_label" ];

   return $stash;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::Messaging - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::Messaging;
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

Copyright (c) 2017 Peter Flanigan. All rights reserved

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
