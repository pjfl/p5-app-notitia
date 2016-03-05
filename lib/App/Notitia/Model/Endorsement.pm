package App::Notitia::Model::Endorsement;

use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind delete_button
                                loc register_action_paths
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
has '+moniker' => default => 'blots';

register_action_paths
   'blots/endorsement'  => 'endorsement',
   'blots/endorsements' => 'endorsements';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Private class attributes
my $_endorsement_links_cache = {};

# Private functions
my $_add_endorsement_button = sub {
   my ($req, $action, $name) = @_;

   return { class => 'fade',
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $action, [ $name ] ),
            name  => 'add_blot',
            tip   => loc( $req, 'add_blot_tip', [ 'endorsement', $name ] ),
            type  => 'link',
            value => loc( $req, 'add_blot' ) };
};

my $_endorsements_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "blots_heading_${_}" ) } } 0 .. 1 ];
};

# Private methods
my $_add_endorsement_js = sub {
   my $self = shift;
   my $opts = { domain => 'schedule', form => 'Endorsement' };

   return [ $self->check_field_server( 'code',     $opts ),
            $self->check_field_server( 'endorsed', $opts ), ];
};

my $_endorsement_links = sub {
   my ($self, $req, $name, $code) = @_;

   my $links = $_endorsement_links_cache->{ $code };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( endorsement ) ) {
      my $path = $self->moniker."/${action}";
      my $href = uri_for_action( $req, $path, [ $name, $code ] );

      push @{ $links }, {
         value => { class => 'table-link fade',
                    hint  => loc( $req, 'Hint' ),
                    href  => $href,
                    name  => "${name}-${action}",
                    tip   => loc( $req, "${action}_management_tip" ),
                    type  => 'link',
                    value => loc( $req, "${action}_management_link" ), }, };
   }

   $_endorsement_links_cache->{ $code } = $links;

   return @{ $links };
};

my $_endorsement_tuple = sub {
   my ($req, $blot) = @_; return [ $blot->label( $req ), $blot ];
};

# Private methods
my $_bind_endorsement_fields = sub {
   my ($self, $blot) = @_;

   my $map     =  {
      code     => { class => 'server' },
      endorsed => { class => 'server' },
      notes    => { class => 'autosize' },
      points   => {},
   };

   return $self->bind_fields( $blot, $map, 'Endorsement' );
};

my $_list_endorsements_for = sub {
   my ($self, $req, $name) = @_;

   my $blots = $self->schema->resultset( 'Endorsement' )->search
      ( { 'recipient.name' => $name },
        { join => [ 'recipient' ], order_by => 'code' } );

   return [ map { $_endorsement_tuple->( $req, $_ ) } $blots->all ];
};

my $_maybe_find_endorsement = sub {
   return $_[ 2 ] ? $_[ 0 ]->find_endorsement_by( $_[ 1 ], $_[ 2 ] )
                  : Class::Null->new;
};

my $_update_endorsement_from_request = sub {
   my ($self, $req, $blot) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   for my $attr (qw( code endorsed notes points )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      length $v and is_member $attr, [ qw( endorsed ) ]
         and $v = str2date_time( $v, 'GMT' );

      $blot->$attr( $v );
   }

   return;
};

# Public functions
sub endorsement : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name       =  $req->uri_params->( 0 );
   my $code       =  $req->uri_params->( 1, { optional => TRUE } );
   my $blot       =  $self->$_maybe_find_endorsement( $name, $code );
   my $page       =  {
      fields      => $self->$_bind_endorsement_fields( $blot ),
      first_field => $code ? 'endorsed' : 'code',
      literal_js  => $self->$_add_endorsement_js(),
      template    => [ 'contents', 'endorsement' ],
      title       => loc( $req, 'endorsement_management_heading' ), };
   my $fields     =  $page->{fields};

   if ($code) {
      $fields->{code  }->{disabled} = TRUE;
      $fields->{delete} = delete_button( $req, $code, 'endorsement' );
   }
   else {
      $fields->{endorsed} = bind( 'endorsed', time2str '%Y-%m-%d' );
   }

   $fields->{save    } = save_button( $req, $code, 'endorsement' );
   $fields->{username} = bind( 'username', $name );

   return $self->get_stash( $req, $page );
}

sub endorsements : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name    =  $req->uri_params->( 0 );
   my $page    =  {
      fields   => { headers  => $_endorsements_headers->( $req ),
                    rows     => [],
                    username => { name => $name }, },
      template => [ 'contents', 'table' ],
      title    => loc( $req, 'endorsements_management_heading' ), };
   my $action  =  $self->moniker.'/endorsement';
   my $rows    =  $page->{fields}->{rows};

   for my $blot (@{ $self->$_list_endorsements_for( $req, $name ) }) {
      push @{ $rows },
         [ { value => $blot->[ 0 ] },
           $self->$_endorsement_links( $req, $name, $blot->[ 1 ]->code ) ];
   }

   $page->{fields}->{add} = $_add_endorsement_button->( $req, $action, $name );

   return $self->get_stash( $req, $page );
}

sub create_endorsement_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0 );
   my $blot_rs = $self->schema->resultset( 'Endorsement' );
   my $blot    = $blot_rs->new_result( { recipient => $name } );

   $self->$_update_endorsement_from_request( $req, $blot ); $blot->insert;

   my $action   = $self->moniker.'/endorsements';
   my $location = uri_for_action( $req, $action, [ $name ] );
   my $message  = [ 'Endorsement [_1] for [_2] added by [_3]',
                    $blot->code, $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_endorsement_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $code     = $req->uri_params->( 1 );
   my $blot     = $self->find_endorsement_by( $name, $code ); $blot->delete;
   my $action   = $self->moniker.'/endorsements';
   my $location = uri_for_action( $req, $action, [ $name ] );
   my $message  = [ 'Endorsement [_1] for [_2] deleted by [_3]',
                    $code, $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub find_endorsement_by {
   my $self = shift; my $rs = $self->schema->resultset( 'Endorsement' );

   return $rs->find_endorsement_by( @_ );
}

sub update_endorsement_action : Role(administrator) Role(person_manager) {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0 );
   my $code = $req->uri_params->( 1 );
   my $blot = $self->find_endorsement_by( $name, $code );

   $self->$_update_endorsement_from_request( $req, $blot ); $blot->update;

   my $message = [ 'Endorsement [_1] for [_2] updated by [_3]',
                   $code, $name, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Endorsement - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Endorsement;
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
