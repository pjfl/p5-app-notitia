package App::Notitia::Model::Certification;

use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind delete_button
                                loc management_button register_action_paths
                                save_button uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Time       qw( str2date_time time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
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

   $stash->{nav} = admin_navigation_links $req;

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

   return [ $self->check_field_server( 'completed', $opts ), ];
};

my $_bind_cert_fields = sub {
   my ($self, $cert) = @_;

   my $map      =  {
      completed => { class => 'server' },
      notes     => { class => 'autosize' },
   };

   return $self->bind_fields( $cert, $map, 'Certification' );
};

my $_cert_links = sub {
   my ($self, $req, $name, $type) = @_;

   my $links = $_cert_links_cache->{ $type };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( certification ) ) {
      my $path = $self->moniker."/${action}";
      my $href = uri_for_action( $req, $path, [ $name, $type ] );

      push @{ $links }, {
         value => management_button( $req, $name, $action, $href ) };
   }

   $_cert_links_cache->{ $type } = $links;

   return @{ $links };
};

my $_cert_tuple = sub {
   my ($req, $cert) = @_; return [ $cert->label( $req ), $cert ];
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
   my ($self, $req, $cert) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   for my $attr (qw( completed notes )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      length $v and is_member $attr, [ qw( completed ) ]
         and $v = str2date_time( $v, 'GMT' );

      $cert->$attr( $v );
   }

   return;
};

# Private methods
my $_list_certification_for = sub {
   my ($self, $req, $name) = @_;

   my $certs = $self->schema->resultset( 'Certification' )->search
      ( { 'recipient.name' => $name },
        { join     => [ 'recipient', 'type' ],
          order_by => 'type.type',
          prefetch => [ 'type' ] } );

   return [ map { $_cert_tuple->( $req, $_ ) } $certs->all ];
};

# Public functions
sub certification : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name      =  $req->uri_params->( 0 );
   my $type      =  $req->uri_params->( 1, { optional => TRUE } );
   my $cert      =  $self->$_maybe_find_cert( $name, $type );
   my $page      =  {
      fields     => $self->$_bind_cert_fields( $cert ),
      literal_js => $self->$_add_certification_js(),
      template   => [ 'contents', 'certification' ],
      title      => loc( $req, 'certification_management_heading' ), };
   my $fields    =  $page->{fields};

   if ($type) {
      my $opts = { disabled => TRUE };

      $fields->{cert_type } = bind( 'cert_type', loc( $req, $type ), $opts );
      $fields->{delete    } = delete_button( $req, $type, 'certification' );
   }
   else {
      $fields->{completed } = bind( 'completed', time2str '%Y-%m-%d' );
      $fields->{cert_types} = bind( 'cert_types', $self->$_list_all_certs() );
   }

   $fields->{save    } = save_button( $req, $type, 'certification' );
   $fields->{username} = bind( 'username', $name );

   return $self->get_stash( $req, $page );
}

sub certifications : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name    =  $req->uri_params->( 0 );
   my $page    =  {
      fields   => { headers  => $_certs_headers->( $req ),
                    rows     => [],
                    username => { name => $name }, },
      template => [ 'contents', 'table' ],
      title    => loc( $req, 'certificates_management_heading' ), };
   my $action  =  $self->moniker.'/certification';
   my $rows    =  $page->{fields}->{rows};

   for my $cert (@{ $self->$_list_certification_for( $req, $name ) }) {
      push @{ $rows },
         [ { value => $cert->[ 0 ] },
           $self->$_cert_links( $req, $name, $cert->[ 1 ]->type ) ];
   }

   $page->{fields}->{add} = $_add_cert_button->( $req, $action, $name );

   return $self->get_stash( $req, $page );
}

sub create_certification_action : Role(administrator) Role(person_manager) {
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

sub delete_certification_action : Role(administrator) Role(person_manager) {
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

sub update_certification_action : Role(administrator) Role(person_manager) {
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
