package App::Notitia::Model::Administration;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE TRUE );
use App::Notitia::Util      qw( loc );
use Class::Null;
use Class::Usul::Functions  qw( is_arrayref is_member throw );
use Class::Usul::Time       qw( str2date_time );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Scalar::Util            qw( blessed );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'admin';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} =
      [ { depth => 0,
          tip   => loc( $req, 'person_administration_tip' ),
          title => loc( $req, 'person_administration' ),
          type  => 'link',
          url   => 'user', },
        { depth => 0,
          tip   => loc( $req, 'vehicle_administration_tip' ),
          title => loc( $req, 'vehicle_administration' ),
          type  => 'link',
          url   => 'vehicle', }, ];

   return $stash;
};

# Private functions
my $_bind = sub {
   my ($name, $v, $opts) = @_; my $class;

   my $params = { label => $name, name => $name };

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $params->{value} = $v->ymd;
   }
   elsif (is_arrayref $v) {
      $params->{value} = [ map { { label => $_, value => $_ } } @{ $v } ];
   }
   else { defined $v and $params->{value} = $v }

   $params->{ $_ } = $opts->{ $_ } for (keys %{ $opts });

   return $params;
};

my $_bind_person_fields = sub {
   my $user = shift;

   return {
      active           => $_bind->( 'active', TRUE,
                                    { checked     => $user->active,
                                      nobreak     => TRUE, } ),
      address          => $_bind->( 'address',       $user->address ),
      dob              => $_bind->( 'dob',           $user->dob ),
      email_address    => $_bind->( 'email_address', $user->email_address ),
      first_name       => $_bind->( 'first_name',    $user->first_name ),
      home_phone       => $_bind->( 'home_phone',    $user->home_phone ),
      joined           => $_bind->( 'joined',        $user->joined ),
      last_name        => $_bind->( 'last_name',     $user->last_name ),
      mobile_phone     => $_bind->( 'mobile_phone',  $user->mobile_phone ),
      next_of_kin      => $_bind->( 'next_of_kin',   $user->next_of_kin,
                                    { disabled    => TRUE } ),
      notes            => $_bind->( 'notes',         $user->notes,
                                    { class       => 'autosize' } ),
      password_expired => $_bind->( 'password_expired', TRUE,
                                    { checked     => $user->password_expired,
                                      container_class => 'right' } ),
      postcode         => $_bind->( 'postcode',      $user->postcode ),
      resigned         => $_bind->( 'resigned',      $user->resigned ),
      roles            => $_bind->( 'roles',         $user->list_roles ),
      subscription     => $_bind->( 'subscription',  $user->subscription ),
      username         => $_bind->( 'username',      $user->name ),
   };
};

my $_bind_save_button = sub {
   my $name = shift; my $k = $name ? 'update' : 'create';

   return { class => 'right', label => $k, value => "${k}_person" };
};

# Private methods
my $_find_user_by_name = sub {
   my ($self, $name) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->search( { name => $name } )->single
      or throw 'User [_1] unknown', [ $name ], rv => HTTP_EXPECTATION_FAILED;

   return $person;
};

# Public methods
sub index {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout => 'index', template => [ 'nav_panel', 'admin' ],
      title  => loc( $req, 'Administration' ) } );
}

sub person {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0, { optional => TRUE } );
   my $user = $name ? $self->$_find_user_by_name( $name ) : Class::Null->new;
   my $page = {
      fields   => $_bind_person_fields->( $user ),
      template => [ 'nav_panel', 'person' ],
      title    => loc( $req, 'person_administration' ), };

   $page->{fields}->{save} = $_bind_save_button->( $name );

   return $self->get_stash( $req, $page );
}

sub vehicle {
   my ($self, $req) = @_;

   my $page = {
      fields   => {},
      template => [ 'nav_panel', 'vehicle' ],
      title    => loc( $req, 'vehicle_administration' ), };

   return $self->get_stash( $req, $page );
}

sub update_person_action {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $user   = $self->$_find_user_by_name( $name );
   my $params = $req->body_params;
   my $args   = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   $user->name( $params->( 'username' ) );

   for my $attr (qw( active address dob email_address first_name home_phone
                     joined last_name mobile_phone notes password_expired
                     postcode resigned subscription )) {
      my $v = $params->( $attr, $args ); defined $v or next;

      is_member $attr, [ qw( dob joined resigned subscription ) ] and length $v
         and $v = str2date_time( "${v} 00:00", 'GMT' );

      $user->$attr( $v );
   }

   $user->update; my $message = [ 'User [_1] updated', $name ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_vehicle_action {
   my ($self, $req) = @_;

   my $params  = $req->body_params;
   my $name    = $params->( 'vrn' );
   my $message = [ 'Vehicle [_1] updated', $name ];

   return { redirect => { location => $req->uri, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Administration - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Administration;
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
