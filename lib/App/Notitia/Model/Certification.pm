package App::Notitia::Model::Certification;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( C_DIALOG EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::DOM       qw( new_container f_tag p_action p_button p_cell
                                p_item p_js p_link p_list p_fields p_radio
                                p_row p_table p_tag p_textfield );
use App::Notitia::Util      qw( check_field_js dialog_anchor loc locm
                                make_tip register_action_paths to_dt to_msg );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Time       qw( time2str );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

# Public attributes
has '+moniker' => default => 'certs';

register_action_paths
   'certs/certification'   => 'certification',
   'certs/certifications'  => 'certifications',
   'certs/upload_document' => 'personal-document';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_certification_js = sub {
   my $opts = { domain => 'schedule', form => 'Certification' };

   return check_field_js 'completed', $opts;
};

my $_certs_headers = sub {
   my $req = shift;

   return [ map { { value => loc $req, "certs_heading_${_}" } } 0 .. 1 ];
};

my $_link_opts = sub {
   return { class => 'operation-links' };
};

my $_personal_docs_headers = sub {
   my $req = shift;

   return [ map { { value => loc $req, "docs_heading_${_}" } } 0 .. 4 ];
};

# Private methods
my $_cert_row = sub {
   my ($self, $req, $scode, $cert) = @_; my $row = [];

   p_item $row, $cert->label( $req );

   my $actionp = $self->moniker.'/certification';
   my $href    = $req->uri_for_action( $actionp, [ $scode, $cert->type ] );
   my $args    = [ $cert->recipient->label ];
   my $cell    = p_cell $row, {}; p_link $cell, 'certification', $href, {
      action => 'update', args => $args, request => $req };

   return $row;
};

my $_certs_ops_links = sub {
   my ($self, $req, $page, $person) = @_; my $links = [];

   p_textfield $links, 'username', $person->label, {
      class => 'narrow-field', disabled => TRUE, label_class => 'left',
      label_field_class => 'label' };

   my $scode = $person->shortcode;
   my $actionp = $self->moniker.'/certification';
   my $params = $req->query_params->( {
      optional => TRUE } ); delete $params->{mid};
   my $href  = $req->uri_for_action( $actionp, [ $scode ], $params );
   my $opts  = { action => 'add', args => [ $person->label ],
                 container_class => 'ops-links right', request => $req };

   p_link $links, 'certification', $href, $opts;

   return $links;
};

my $_file_row = sub {
   my ($self, $req, $scode, $path) = @_; my $row = [];

   my $conf = $self->config;
   my $file = $path->filename;
   my $href = $req->uri_for( $conf->assets."/personal/${scode}/${file}" );
   my $cell = p_cell $row, { class => 'narrow align-center' };
   my $tip  = locm $req, 'download_document_tip';

   p_link $cell, $file, $href, {
      action => 'download', download => $file, request => $req, tip => $tip,
      value  => f_tag 'i', NUL, { class => 'download-icon', close => TRUE },
   };

   $cell = p_cell $row, {}; $tip = locm $req, 'view_document_tip';

   p_link $cell, "view_${file}", $href, {
      request => $req, tip => $tip, value => $file };

   p_item $row, $path->stat->{size}, { class => 'narrow align-right' };

   p_item $row, time2str( '%Y-%m-%d %H:%M:%S', $path->stat->{mtime} ), {
      class => 'file-date align-right' };

   $cell = p_cell $row, { class => 'narrow align-center' };

   p_radio $cell, 'selected', [ [ NUL, $file ] ], { label => NUL };

   return $row;
};

my $_files_action_links = sub {
   my ($self, $req, $page, $person) = @_; my $links = [];

   p_button $links, 'delete', 'delete_document', {
      class => 'button', container_class => 'right',
      tip => make_tip $req, 'delete_document_tip',
   };

   return $links;
};

my $_files_ops_links = sub {
   my ($self, $req, $page, $person) = @_; my $links = [];

   p_tag $links, 'h4', 'Personal Documents', { class => 'label left' };

   p_link $links, 'document', C_DIALOG, {
      action => 'upload', args => [ $person->label ],
      container_class => 'action-links right', request => $req };

   my $actionp = $self->moniker.'/upload_document';
   my $href = $req->uri_for_action( $actionp, [ $person->shortcode ] );

   p_js $page, dialog_anchor 'upload_document', $href, {
      name => 'document_upload', title => loc $req, 'Document Upload' };

   return $links;
};

my $_list_all_certs = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search_for_certification_types->all ];
};

my $_maybe_find_cert = sub {
   my ($self, $name, $type) = @_;

   return $type ? $self->find_cert_by( $name, $type ) : Class::Null->new;
};

my $_update_cert_from_request = sub {
   my ($self, $req, $cert) = @_;

   my $opts = { optional => TRUE }; my $params = $req->body_params;

   for my $attr (qw( completed notes )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts );

      defined $v or next; $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      length $v and is_member $attr, [ qw( completed ) ] and $v = to_dt $v;

      $cert->$attr( $v );
   }

   return;
};

my $_bind_cert_fields = sub {
   my ($self, $cert, $opts) = @_;

   my $updating  = $opts->{action} eq 'update' ? TRUE : FALSE;
   my $completed = $updating ? $cert->completed : to_dt time2str '%Y-%m-%d';

   return
   [  cert_type   => !$updating ? FALSE : {
         disabled => TRUE, value => loc $opts->{request}, $cert->type },
      cert_types  => $updating ? FALSE : {
         type     => 'select', value => $self->$_list_all_certs() },
      completed   => { class => 'standard-field server', type => 'date',
                       value => $completed },
      notes       => { class => 'standard-field autosize', type => 'textarea' },
      ];
};

# Public functions
sub certification : Role(person_manager) Role(training_manager) {
   my ($self, $req) = @_;

   my $actionp   =  $self->moniker.'/certification';
   my $scode     =  $req->uri_params->( 0 );
   my $type      =  $req->uri_params->( 1, { optional => TRUE } );
   my $role      =  $req->query_params->( 'role', { optional => TRUE } );
   my $href      =  $req->uri_for_action( $actionp, [ $scode, $type ] );
   my $form      =  new_container 'certification-admin', $href;
   my $action    =  $type ? 'update' : 'create';
   my $page      =  {
      forms      => [ $form ],
      selected   => $role ? "${role}_list" : 'people_list',
      title      => loc $req, "certification_${action}_heading" };
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $person    =  $person_rs->find_by_shortcode( $scode );
   my $cert      =  $self->$_maybe_find_cert( $scode, $type );
   my $args      =  [ 'certification', $person->label ];

   p_js $page, $_certification_js->();

   p_textfield $form, 'username', $person->label, { disabled => TRUE };

   p_fields $form, $self->schema, 'Certification', $cert,
      $self->$_bind_cert_fields( $cert, { action => $action, request => $req });

   p_action $form, $action, $args, { request => $req };

   $type and p_action $form, 'delete', $args, { request => $req };

   return $self->get_stash( $req, $page );
}

sub certifications : Role(person_manager) Role(training_manager) {
   my ($self, $req) = @_;

   my $scode   =  $req->uri_params->( 0 );
   my $actionp =  $self->moniker.'/certifications';
   my $href    =  $req->uri_for_action( $actionp, [ $scode ] );
   my $role    =  $req->query_params->( 'role', { optional => TRUE } );
   my $form    =  new_container 'certifications', $href, { class => 'wide-form' };
   my $page    =  {
      forms    => [ $form ],
      selected => $role ? "${role}_list" : 'people_list',
      title    => loc $req, 'certificates_management_heading' };
   my $schema  =  $self->schema;
   my $person  =  $schema->resultset( 'Person' )->find_by_shortcode( $scode );
   my $links   =  $self->$_certs_ops_links( $req, $page, $person );

   p_list $form, NUL, $links, $_link_opts->();

   my $cert_rs =  $schema->resultset( 'Certification' );
   my $table   =  p_table $form, { headers => $_certs_headers->( $req ) };

   p_row $table, [ map { $self->$_cert_row( $req, $scode, $_ ) }
                   $cert_rs->search_for_certifications( $scode )->all ];

   $links = $self->$_files_ops_links( $req, $page, $person );
   p_list $form, NUL, $links, $_link_opts->();

   $table = p_table $form, { headers => $_personal_docs_headers->( $req ) };

   my $assetdir = $self->config->assetdir;
   my $userdir  = $assetdir->catdir( 'personal' )->catdir( $scode );

   $userdir->exists or return $self->get_stash( $req, $page );

   p_row $table, [ map { $self->$_file_row( $req, $scode, $_ ) }
                   $userdir->all_files ];

   $links = $self->$_files_action_links( $req, $page, $person );
   p_list $form, NUL, $links, $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub create_certification_action : Role(person_manager) Role(training_manager) {
   my ($self, $req) = @_;

   my $scode   = $req->uri_params->( 0 );
   my $type    = $req->body_params->( 'cert_types' );
   my $cert_rs = $self->schema->resultset( 'Certification' );
   my $cert    = $cert_rs->new_result( { recipient => $scode, type => $type } );

   $self->$_update_cert_from_request( $req, $cert );

   my $label   = $cert->label( $req );

   try   { $cert->insert }
   catch { $self->blow_smoke( $_, 'create', 'certification', $label ) };

   my $message  = "action:create-certification shortcode:${scode} type:${type}";

   $self->send_event( $req, $message );

   my $actionp  = $self->moniker.'/certifications';
   my $location = $req->uri_for_action( $actionp, [ $scode ] );
   my $key      = 'Certertification [_1] for [_2] added by [_3]';

   $message = [ to_msg $key, $type, $scode, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_certification_action : Role(person_manager) Role(training_manager) {
   my ($self, $req) = @_;

   my $scode    = $req->uri_params->( 0 );
   my $type     = $req->uri_params->( 1 );
   my $cert     = $self->find_cert_by( $scode, $type ); $cert->delete;
   my $message  = "action:delete-certification shortcode:${scode} type:${type}";

   $self->send_event( $req, $message );

   my $action   = $self->moniker.'/certifications';
   my $location = $req->uri_for_action( $action, [ $scode ] );
   my $key      = 'Certification [_1] for [_2] deleted by [_3]';

   $message = [ to_msg $key, $type, $scode, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_document_action : Role(person_manager) Role(training_manager) {
   my ($self, $req) = @_; my $message;

   my $scode = $req->uri_params->( 0 );
   my $file  = $req->body_params->( 'selected', { optional => TRUE } );

   if ($file) {
      my $dir  = $self->config->assetdir;
      my $path = $dir->catdir( 'personal' )->catdir( $scode )->catfile( $file );

      if ($path->exists) {
         $path->unlink; $message = [ to_msg 'Document [_1] deleted', $file ];
      }
      else { $message = [ to_msg 'Document [_1] does not exist', $file ] }
   }
   else { $message = [ to_msg 'No document selected' ] }

   return { redirect => { location => $req->uri, message => $message } };
}

sub find_cert_by {
   my $self = shift; my $rs = $self->schema->resultset( 'Certification' );

   return $rs->find_cert_by( @_ );
}

sub update_certification_action : Role(person_manager) Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $type  = $req->uri_params->( 1 );
   my $cert  = $self->find_cert_by( $scode, $type );

   $self->$_update_cert_from_request( $req, $cert ); $cert->update;

   my $message = "action:update-certification shortcode:${scode} type:${type}";

   $self->send_event( $req, $message );

   my $key  = 'Certification [_1] for [_2] updated by [_3]';

   $message = [ to_msg $key, $type, $scode, $req->session->user_label ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub upload_document : Dialog Role(person_manager) Role(training_manager) {
   my ($self, $req) = @_;

   my $scode  = $req->uri_params->( 0 );
   my $stash  = $self->dialog_stash( $req );
   my $params = { name => $scode, type => 'personal' };
   my $places = $self->config->places;
   my $href   = $req->uri_for_action( $places->{upload}, [], $params );

   $stash->{page}->{forms}->[ 0 ] = new_container 'upload-file', $href;
   $self->components->{docs}->upload_dialog( $req, $stash->{page} );

   return $stash;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Certification - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Certification;
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
