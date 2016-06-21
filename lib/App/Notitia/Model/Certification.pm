package App::Notitia::Model::Certification;

use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP TRUE );
use App::Notitia::Form      qw( blank_form f_link p_action p_list p_fields
                                p_row p_table p_textfield );
use App::Notitia::Util      qw( check_field_js loc locm register_action_paths
                                to_dt to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Time       qw( time2str );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'certs';

register_action_paths
   'certs/certification'  => 'certification',
   'certs/certifications' => 'certifications';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_certs_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "certs_heading_${_}" ) } } 0 .. 1 ];
};

my $_certs_ops_links = sub {
   my ($req, $actionp, $person) = @_;

   my $href = uri_for_action( $req, $actionp, [ $person->shortcode ] );
   my $opts = { action => 'add', args => [ $person->label ], request => $req };

   return [ f_link 'certification', $href, $opts ];
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

# Private methods
my $_cert_links = sub {
   my ($self, $req, $scode, $cert) = @_;

   my $args = [ $cert->recipient->label ]; my @links;

   for my $actionp (map { $self->moniker."/${_}" } 'certification' ) {
      my $href = uri_for_action $req, $actionp, [ $scode, $cert->type ];
      my $opts = { action => 'update', args => $args, request => $req };

      push @links, { value => f_link 'certification', $href, $opts };
   }

   return [ { value => $cert->label( $req ) }, @links ];
};

my $_certification_js = sub {
   my $self = shift;
   my $opts = { domain => 'schedule', form => 'Certification' };

   return [ check_field_js( 'completed', $opts ), ];
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
sub certification : Role(person_manager) {
   my ($self, $req) = @_;

   my $actionp   =  $self->moniker.'/certification';
   my $name      =  $req->uri_params->( 0 );
   my $type      =  $req->uri_params->( 1, { optional => TRUE } );
   my $href      =  uri_for_action $req, $actionp, [ $name, $type ];
   my $form      =  blank_form 'certification-admin', $href;
   my $action    =  $type ? 'update' : 'create';
   my $page      =  {
      forms      => [ $form ],
      literal_js => $self->$_certification_js(),
      title      => loc $req, "certification_${action}_heading" };
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $person    =  $person_rs->find_by_shortcode( $name );
   my $cert      =  $self->$_maybe_find_cert( $name, $type );
   my $args      =  [ 'certification', $person->label ];

   p_textfield $form, 'username', $person->label, { disabled => TRUE };

   p_fields $form, $self->schema, 'Certification', $cert,
      $self->$_bind_cert_fields( $cert, { action => $action, request => $req });

   p_action $form, $action, $args, { request => $req };

   $type and p_action $form, 'delete', $args, { request => $req };

   return $self->get_stash( $req, $page );
}

sub certifications : Role(person_manager) {
   my ($self, $req) = @_;

   my $actionp =  $self->moniker.'/certification';
   my $scode   =  $req->uri_params->( 0 );
   my $form    =  blank_form;
   my $page    =  {
      forms    => [ $form ],
      title    => loc $req, 'certificates_management_heading' };
   my $schema  =  $self->schema;
   my $person  =  $schema->resultset( 'Person' )->find_by_shortcode( $scode );
   my $cert_rs =  $schema->resultset( 'Certification' );
   my $links   =  $_certs_ops_links->( $req, $actionp, $person );

   p_textfield $form, 'username', $person->label, { disabled => TRUE };

   my $table = p_table $form, { headers => $_certs_headers->( $req ) };

   p_row $table, [ map { $self->$_cert_links( $req, $scode, $_ ) }
                   $cert_rs->search_for_certifications( $scode )->all ];

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub create_certification_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0 );
   my $type    = $req->body_params->( 'cert_types' );
   my $cert_rs = $self->schema->resultset( 'Certification' );
   my $cert    = $cert_rs->new_result( { recipient => $name, type => $type } );

   $self->$_update_cert_from_request( $req, $cert );

   try   { $cert->insert }
   catch {
      $self->rethrow_exception
         ( $_, 'create', 'certification', $cert->label( $req ) );
   };

   my $action   = $self->moniker.'/certifications';
   my $location = uri_for_action( $req, $action, [ $name ] );
   my $who      = $req->session->user_label;
   my $message  =
      [ to_msg 'Cert. [_1] for [_2] added by [_3]', $type, $name, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_certification_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $type     = $req->uri_params->( 1 );
   my $cert     = $self->find_cert_by( $name, $type ); $cert->delete;
   my $action   = $self->moniker.'/certifications';
   my $location = uri_for_action( $req, $action, [ $name ] );
   my $who      = $req->session->user_label;
   my $message  =
      [ to_msg 'Cert. [_1] for [_2] deleted by [_3]', $type, $name, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub find_cert_by {
   my $self = shift; my $rs = $self->schema->resultset( 'Certification' );

   return $rs->find_cert_by( @_ );
}

sub update_certification_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0 );
   my $type = $req->uri_params->( 1 );
   my $cert = $self->find_cert_by( $name, $type );

   $self->$_update_cert_from_request( $req, $cert ); $cert->update;

   my $who     = $req->session->user_label;
   my $message =
      [ to_msg 'Cert. [_1] for [_2] updated by [_3]', $type, $name, $who ];

   return { redirect => { location => $req->uri, message => $message } };
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
