package App::Notitia::Model::Certification;

use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( bind bind_fields check_field_server
                                delete_button loc management_link
                                register_action_paths save_button
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Time       qw( time2str );
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

   $stash->{nav }->{list    } = $self->admin_navigation_links( $req );
   $stash->{page}->{location} = 'admin';

   return $stash;
};

# Private class attributes
my $_cert_links_cache = {};

# Private functions
my $_add_cert_button = sub {
   my ($req, $action, $name) = @_;

   return { class => 'fade',
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $action, [ $name ] ),
            name  => 'add_cert',
            tip   => loc( $req, 'add_cert_tip', [ 'certification', $name ] ),
            type  => 'link',
            value => loc( $req, 'add_cert' ) };
};

my $_certs_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "certs_heading_${_}" ) } } 0 .. 1 ];
};

# Private methods
my $_add_certification_js = sub {
   my $self = shift;
   my $opts = { domain => 'schedule', form => 'Certification' };

   return [ check_field_server( 'completed', $opts ), ];
};

my $_bind_cert_fields = sub {
   my ($self, $cert) = @_;

   my $map      =  {
      completed => { class => 'standard-field server' },
      notes     => { class => 'standard-field autosize' },
   };

   return bind_fields $self->schema, $cert, $map, 'Certification';
};

my $_cert_links = sub {
   my ($self, $req, $name, $type) = @_;

   my $links = $_cert_links_cache->{ $type }; $links and return @{ $links };

   my $opts = { args => [ $name, $type ] }; $links = [];

   for my $actionp (map { $self->moniker."/${_}" } 'certification' ) {
      push @{ $links }, {
         value => management_link( $req, $actionp, $name, $opts ) };
   }

   $_cert_links_cache->{ $type } = $links;

   return @{ $links };
};

my $_list_all_certs = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->list_certification_types->all ];
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

      length $v and is_member $attr, [ qw( completed ) ]
         and $v = $self->to_dt( $v );

      $cert->$attr( $v );
   }

   return;
};

# Public functions
sub certification : Role(person_manager) {
   my ($self, $req) = @_;

   my $name      =  $req->uri_params->( 0 );
   my $type      =  $req->uri_params->( 1, { optional => TRUE } );
   my $cert      =  $self->$_maybe_find_cert( $name, $type );
   my $page      =  {
      fields     => $self->$_bind_cert_fields( $cert ),
      literal_js => $self->$_add_certification_js(),
      template   => [ 'contents', 'certification' ],
      title      => loc( $req, $type ? 'certification_edit_heading'
                                     : 'certification_create_heading' ), };
   my $fields    =  $page->{fields};
   my $args      =  [ $name ];

   if ($type) {
      my $opts = { disabled => TRUE }; $args = [ $name, $type ];

      $fields->{cert_type} = bind 'cert_type', loc( $req, $type ), $opts;
      $fields->{delete} = delete_button $req, $type, { type => 'certification'};
   }
   else {
      $fields->{completed } = bind 'completed', time2str '%Y-%m-%d';
      $fields->{cert_types} = bind 'cert_types', $self->$_list_all_certs();
   }

   $fields->{save} = save_button $req, $type, { type => 'certification' };
   $fields->{href} = uri_for_action $req, 'certs/certification', $args;

   return $self->get_stash( $req, $page );
}

sub certifications : Role(person_manager) {
   my ($self, $req) = @_;

   my $name    =  $req->uri_params->( 0 );
   my $page    =  {
      fields   => { headers  => $_certs_headers->( $req ),
                    rows     => [],
                    username => { name => $name }, },
      template => [ 'contents', 'table' ],
      title    => loc( $req, 'certificates_management_heading' ), };
   my $cert_rs =  $self->schema->resultset( 'Certification' );
   my $actionp =  $self->moniker.'/certification';
   my $rows    =  $page->{fields}->{rows};

   $page->{fields}->{add} = $_add_cert_button->( $req, $actionp, $name );

   for my $cert (@{ $cert_rs->list_certification_for( $req, $name ) }) {
      push @{ $rows },
         [ { value => $cert->[ 0 ] },
           $self->$_cert_links( $req, $name, $cert->[ 1 ]->type ) ];
   }

   return $self->get_stash( $req, $page );
}

sub create_certification_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0 );
   my $type    = $req->body_params->( 'cert_types' );
   my $cert_rs = $self->schema->resultset( 'Certification' );
   my $cert    = $cert_rs->new_result( { recipient => $name, type => $type } );

   $self->$_update_cert_from_request( $req, $cert ); $cert->insert;

   my $action   = $self->moniker.'/certifications';
   my $location = uri_for_action( $req, $action, [ $name ] );
   my $message  =
      [ 'Cert. [_1] for [_2] added by [_3]', $type, $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_certification_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $type     = $req->uri_params->( 1 );
   my $cert     = $self->find_cert_by( $name, $type ); $cert->delete;
   my $action   = $self->moniker.'/certifications';
   my $location = uri_for_action( $req, $action, [ $name ] );
   my $message  = [ 'Cert. [_1] for [_2] deleted by [_3]',
                    $type, $name, $req->username ];

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

   my $message = [ 'Cert. [_1] for [_2] updated by [_3]',
                   $type, $name, $req->username ];

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
