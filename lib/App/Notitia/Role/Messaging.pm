package App::Notitia::Role::Messaging;

use namespace::autoclean;

use App::Notitia::Form      qw( blank_form p_button p_radio
                                p_select p_textarea );
use App::Notitia::Constants qw( NUL SPC TRUE );
use App::Notitia::Util      qw( js_config loc mail_domain
                                table_link to_msg uri_for_action );
use Class::Usul::File;
use Class::Usul::Functions  qw( create_token throw );
use Moo::Role;

requires qw( config dialog_stash moniker );

# Private functions
my $_plate_label = sub {
   my $v = ucfirst $_[ 0 ]->basename( '.md' ); $v =~ s{[_\-]}{ }gmx; return $v;
};

# Private methods
my $_session_file = sub {
   return $_[ 0 ]->config->sessdir->catfile( substr create_token, 0, 32 );
};

my $_flatten_stash = sub {
   my ($self, $v) = @_; my $path = $self->$_session_file;

   my $params = { data => $v, path => $path->assert, storage_class => 'JSON' };

   Class::Usul::File->data_dump( $params );

   return "-o stash=${path} ";
};

my $_create_send_email_job = sub {
   my ($self, $stash, $template) = @_; my $conf = $self->config;

   my $cmd = $conf->binsdir->catfile( 'notitia-schema' ).SPC
           . $self->$_flatten_stash( $stash )."send_message email ${template}";
   my $rs  = $self->schema->resultset( 'Job' );

   return $rs->create( { command => $cmd, name => 'send_message' } );
};

my $_flatten = sub {
   my ($self, $req) = @_;

   my $selected = $req->body_params->( 'selected',
                                       { optional => TRUE, multiple => TRUE } );
   my $params   = $req->query_params->( { optional => TRUE } ) // {};
   my $r        = NUL; delete $params->{mid};

   if (defined $selected->[ 0 ]) {
      my $path = $self->$_session_file;
      my $opts = { data => { selected => $selected },
                   path => $path->assert, storage_class => 'JSON' };

      Class::Usul::File->data_dump( $opts ); $r = "-o recipients=${path} ";
   }
   else {
      scalar keys %{ $params } or throw 'Messaging all people is not allowed';

      exists $params->{type} and $params->{type} eq 'contacts'
         and throw 'Messaging all contacts is not allowed';

      for my $k (keys %{ $params }) { $r .= "-o ${k}=".$params->{ $k }.' ' }
   }

   return $r;
};

my $_list_message_templates = sub {
   my ($self, $req) = @_;

   my $conf   = $self->config;
   my $dir    = $conf->docs_root->catdir
      ( $req->locale, $conf->posts, $conf->drafts );
   my $plates = $dir->filter( sub { m{ \.md \z }mx } );

   $dir->exists or return [ [ NUL, NUL ] ];

   return [ map { [ $_plate_label->( $_ ), "${_}" ] } $plates->all_files ];
};

my $_make_template = sub {
   my ($self, $message) = @_;

   my $path = $self->$_session_file; $path->print( $message );

   return $path;
};

my $_template_path = sub {
   my ($self, $name) = @_; my $conf = $self->config;

   return $conf->template_dir->catfile( $conf->skin."/${name}.tt" );
};

# Public methods
sub create_person_email {
   my ($self, $req, $person, $password) = @_;

   my $conf     = $self->config;
   my $scode    = $person->shortcode;
   my $token    = substr create_token, 0, 32;
   my $key      = 'Account activation for [_2]@[_1]';
   my $template = $self->$_template_path( 'user_email' );
   my $subject  = loc $req, to_msg $key, $conf->title, $person->name;
   my $link     = uri_for_action $req, $self->moniker.'/activate', [ $token ];
   my $stash    = { app_name => $conf->title, link      => $link,
                    password => $password,    shortcode => $scode,
                    subject  => $subject, };

   $conf->sessdir->catfile( $token )->println( $scode );

   return $self->$_create_send_email_job( $stash, $template )->id;
}

sub create_reset_email {
   my ($self, $req, $person, $password) = @_;

   my $conf     = $self->config;
   my $scode    = $person->shortcode;
   my $token    = substr create_token, 0, 32;
   my $key      = 'Password reset for [_2]@[_1]';
   my $template = $self->$_template_path( 'password_email' );
   my $subject  = loc $req, to_msg $key, $conf->title, $person->name;
   my $link     = uri_for_action $req, $self->moniker.'/reset', [ $token ];
   my $stash    = { app_name => $conf->title, link      => $link,
                    password => $password,    shortcode => $scode,
                    subject  => $subject, };

   $conf->sessdir->catfile( $token )->println( "${scode}/${password}" );

   return $self->$_create_send_email_job( $stash, $template )->id;
}

sub create_totp_request_email {
   my ($self, $req, $person) = @_;

   my $conf     = $self->config;
   my $scode    = $person->shortcode;
   my $token    = substr create_token, 0, 32;
   my $key      = 'TOTP Request for [_2]@[_1]';
   my $template = $self->$_template_path( 'totp_request_email' );
   my $subject  = loc $req, to_msg $key, $conf->title, $person->name;
   my $link     = uri_for_action $req, $self->moniker.'/totp_secret', [ $token];
   my $stash    = { app_name  => $conf->title, link    => $link,
                    shortcode => $scode,       subject => $subject, };

   $conf->sessdir->catfile( $token )->println( $scode );

   return $self->$_create_send_email_job( $stash, $template )->id;
}

sub message_create {
   my ($self, $req, $params) = @_;

   my $conf     = $self->config;
   my $sink     = $req->body_params->( 'sink' );
   my $opts     = $sink eq 'sms' ? { optional => TRUE } : {};
   my $template = $req->body_params->( 'template', $opts );
      $opts     = $sink eq 'email' ? { optional => TRUE } : {};
   my $message  = $req->body_params->( 'sms_message', $opts );

   $sink eq 'sms' and $template = $self->$_make_template( $message );

   my $cmd      = $conf->binsdir->catfile( 'notitia-schema' ).SPC
                . $self->$_flatten( $req )."send_message ${sink} ${template}";
   my $job_rs   = $self->schema->resultset( 'Job' );
   my $job      = $job_rs->create( { command => $cmd, name => 'send_message' });
      $message  = [ to_msg 'Job send_message-[_1] created', $job->id ];
   my $location = uri_for_action $req, $self->moniker.'/'.$params->{action};

   return { redirect => { location => $location, message => $message } };
}

sub message_link {
   my ($self, $req, $page, $href, $name) = @_;

   my $opts   =  {
      name    => $name,
      target  => $page->{form}->{name},
      title   => loc( $req, 'message_title' ),
      useIcon => \1 };
   my $args   =  [ "${href}", $opts ];

   js_config $page, 'window', [ 'message', 'click', 'inlineDialog', $args ];
   $args = [ 'email_sink', 'email_sink_label' ];
   $opts = [ 'email_sink', 'checked', 'showSelected', $args ];
   js_config $page, 'togglers', $opts;
   $args = [ 'sms_sink', 'sms_sink_label' ];
   $opts = [ 'sms_sink', 'checked', 'showSelected', $args ];
   js_config $page, 'togglers', $opts;

   return table_link $req, 'message', loc( $req, 'message_management_link' ),
                                      loc( $req, 'message_management_tip' );
}

sub message_stash {
   my ($self, $req, $opts) = @_;

   my $params    = $req->query_params->( { optional => TRUE } ) // {};
   my $stash     = $self->dialog_stash( $req, 'message-people' );
   my $form      = $stash->{page}->{forms}->[ 0 ]
                 = blank_form NUL, { class => 'standard-form' };
   my $templates = $self->$_list_message_templates( $req );
   my $values    =
      [ [ 'Email', 'email', { class    => 'togglers', id => 'email_sink',
                              selected => TRUE } ],
        [ 'SMS',   'sms',   { class    => 'togglers', id => 'sms_sink' } ] ];

   delete $params->{id}; delete $params->{val};

   p_radio $form, 'sink', $values, { label => 'Message sink' };

   p_select $form, 'template', [ [ NUL, NUL ], @{ $templates } ], {
      label_id => 'email_sink_label' };

   p_textarea $form, 'sms_message', NUL, {
      class    => 'standard-field clear autosize', label_class => 'hidden',
      label_id => 'sms_sink_label' };

   p_button $form, 'confirm', 'message_create', { class => 'right-last' };

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
