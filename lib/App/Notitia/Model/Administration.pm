package App::Notitia::Model::Administration;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TILDE TRUE );
use App::Notitia::Util      qw( loc );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_arrayref is_member throw );
use Class::Usul::Time       qw( str2date_time );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Scalar::Util            qw( blessed );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);

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
my $_bind_option = sub {
   my ($v, $prefix, $numify) = @_;

   return is_arrayref $v
        ? { label => $v->[ 0 ].NUL, selected => $v->[ 2 ],
            value => ($v->[ 1 ] ? ($numify ? 0 + $v->[ 1 ] : $prefix.$v->[ 1 ])
                                : undef) }
        : { label => "${v}", value => ($numify ? 0 + $v : $prefix.$v) };
};

my $_bind = sub {
   my ($name, $v, $opts) = @_; $opts //= {};

   my $prefix = delete $opts->{prefix} // NUL;
   my $numify = delete $opts->{numify} // FALSE;
   my $params = { label => $name, name => $name }; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $params->{value} = $v->ymd;
   }
   elsif (is_arrayref $v) {
      $params->{value}
         = [ map { $_bind_option->( $_, $prefix, $numify ) } @{ $v } ];
   }
   else { defined $v and $params->{value} = $numify ? 0 + $v : "${v}" }

   $params->{ $_ } = $opts->{ $_ } for (keys %{ $opts });

   return $params;
};

my $_bind_person_fields = sub {
   my $person = shift;

   return {
      active           => $_bind->( 'active', TRUE,
                                    { checked     => $person->active,
                                      nobreak     => TRUE, } ),
      address          => $_bind->( 'address',       $person->address ),
      dob              => $_bind->( 'dob',           $person->dob ),
      email_address    => $_bind->( 'email_address', $person->email_address ),
      first_name       => $_bind->( 'first_name',    $person->first_name ),
      home_phone       => $_bind->( 'home_phone',    $person->home_phone ),
      joined           => $_bind->( 'joined',        $person->joined ),
      last_name        => $_bind->( 'last_name',     $person->last_name ),
      mobile_phone     => $_bind->( 'mobile_phone',  $person->mobile_phone ),
      notes            => $_bind->( 'notes',         $person->notes,
                                    { class       => 'autosize' } ),
      password_expired => $_bind->( 'password_expired', TRUE,
                                    { checked     => $person->password_expired,
                                      container_class => 'right' } ),
      postcode         => $_bind->( 'postcode',      $person->postcode ),
      resigned         => $_bind->( 'resigned',      $person->resigned ),
      subscription     => $_bind->( 'subscription',  $person->subscription ),
      username         => $_bind->( 'username',      $person->name ),
   };
};

my $_delete_person_button = sub {
   my ($req, $name) = @_;

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, 'delete_tip', [ 'person', $name ] );

   return { container_class => 'right', label => 'delete',
            tip => $tip, value => 'delete_person' };
};

my $_save_person_button = sub {
   my ($req, $name) = @_; my $k = $name ? 'update' : 'create';

   my $tip = loc( $req, 'Hint' ).SPC.TILDE.SPC
           . loc( $req, "${k}_tip", [ 'person', $name ] );

   return { container_class => 'right', label => $k,
            tip => $tip, value => "${k}_person" };
};

my $_select_next_of_kin_list = sub {
   return $_bind->( 'next_of_kin', $_[ 0 ], { numify => TRUE } );
};

my $_select_person_list = sub {
   return $_bind->( 'select_person', $_[ 0 ],
                    { onchange => TRUE, prefix => 'user/' } );
};

# Private methods
my $_create_user_email = sub {
   my ($self, $req, $person, $password) = @_;

   my $conf    = $self->config;
   my $key     = substr create_token, 0, 32;
   my $opts    = { params => [ $conf->title ], no_quote_bind_values => TRUE };
   my $from    = loc( $req, 'UserRegistration@[_1]', $opts );
   my $subject = loc( $req, 'Account activation for [_1]', $opts );
   my $post    = {
      attributes      => {
         charset      => $conf->encoding,
         content_type => 'text/html', },
      from            => $from,
      stash           => {
         app_name     => $conf->title,
         first_name   => $person->first_name,
         link         => $req->uri_for( 'user/activate', [ $key ] ),
         password     => $password,
         title        => $subject,
         username     => $person->name, },
      subject         => $subject,
      template        => 'user_email',
      to              => $person->email_address, };

   $conf->sessdir->catfile( $key )->println( $person->name );

   my $r = $self->send_email( $post );
   my ($id) = $r =~ m{ ^ OK \s+ id= (.+) $ }msx; chomp $id;

   $self->log->info( loc( $req, 'New user email sent - [_1]', [ $id ] ) );

   return;
};

my $_find_person_by = sub {
   my ($self, $name) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->search( { name => $name } )->single
      or throw 'User [_1] unknown', [ $name ], rv => HTTP_EXPECTATION_FAILED;

   return $person;
};

my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search
            ( { type => 'role' }, { columns => [ 'name' ] } )->all ];
};

my $_person_tuple = sub {
   my ($person, $selected) = @_; $selected //= 0;

   my $label = $person->first_name.SPC.$person->last_name." (${person})";

   return [ $label, $person, ($selected eq $person ? TRUE : FALSE) ];
};

my $_list_all_people = sub {
   my ($self, $selected) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my @people    = map { $_person_tuple->( $_, $selected ) } $person_rs->search
      ( {}, { columns => [ 'first_name', 'id', 'last_name', 'name' ] } )->all;

   return [ [ NUL, NUL ], @people ];
};

my $_update_person_from_request = sub {
   my ($self, $req, $person) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   $person->name( $params->( 'username' ) );

   for my $attr (qw( active address dob email_address first_name home_phone
                     joined last_name mobile_phone notes
                     password_expired postcode resigned subscription )) {
      my $v = $params->( $attr, $opts );

      not defined $v and is_member $attr, [ qw( active password_expired ) ]
          and $v = FALSE;

      defined $v or next;

      length $v and is_member $attr, [ qw( dob joined resigned subscription ) ]
         and $v = str2date_time( "${v} 00:00", 'GMT' );

      $person->$attr( $v );
   }

   my $v = $params->( 'next_of_kin', $opts ) or return;

   $person->id and $v == $person->id
      and throw 'Cannot set self as next of kin', rv => HTTP_EXPECTATION_FAILED;

   $person->next_of_kin( $v );
   return;
};

# Public methods
sub activate {
   my ($self, $req) = @_;

   my $file = $self->config->sessdir->catfile( $req->uri_params->( 0 ) );
   my $name = $file->chomp->getline; $file->unlink;

   $self->$_find_person_by( $name )->activate;

   my $location = $req->uri_for( "user/password/${name}" );
   my $message  = [ 'User [_1] account activated', $name ];

   return { redirect => { location => $location, message => $message } };
}

sub create_person_action {
   my ($self, $req) = @_;

   my $person = $self->schema->resultset( 'Person' )->new_result( {} );

   $self->$_update_person_from_request( $req, $person );

   my $role = $req->body_params->( 'roles' );

   $person->password( my $password = substr create_token, 0, 12 );
   $person->password_expired( TRUE );
   $person->insert;
   # TODO: This can throw which will fuck shit up. Needs a transaction
   $person->add_member_to( $role );

   $self->config->no_user_email
      or $self->$_create_user_email( $req, $person, $password );

   my $location = $req->uri_for( 'user/'.$person->name );
   my $message  = [ 'User [_1] created', $person->name ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->$_find_person_by( $name ); $person->delete;
   my $location = $req->uri_for( 'user' );
   my $message  = [ 'User [_1] deleted', $name ];

   return { redirect => { location => $location, message => $message } };
}

sub index {
   my ($self, $req) = @_;

   return $self->get_stash( $req, {
      layout => 'index', template => [ 'nav_panel', 'admin' ],
      title  => loc( $req, 'Administration' ) } );
}

sub person {
   my ($self, $req) = @_; my $people;

   my $name    =  $req->uri_params->( 0, { optional => TRUE } );
   my $person  =  $name ? $self->$_find_person_by( $name ) : Class::Null->new;
   my $page    =  {
      fields   => $_bind_person_fields->( $person ),
      template => [ 'nav_panel', 'person' ],
      title    => loc( $req, 'person_administration' ), };
   my $fields  =  $page->{fields};

   if ($name) {
      $people = $self->$_list_all_people( $person->next_of_kin );
      $fields->{delete} = $_delete_person_button->( $req, $name );
      $fields->{roles } = $_bind->( 'roles', $person->list_roles );
   }
   else {
      $people = $self->$_list_all_people();
      $fields->{roles } = $_bind->( 'roles', $self->$_list_all_roles() );
      $fields->{select} = $_select_person_list->( $people );
   }

   $fields->{next_of_kin} = $_select_next_of_kin_list->( $people );
   $fields->{save       } = $_save_person_button->( $req, $name );

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
   my $person = $self->$_find_person_by( $name );

   $self->$_update_person_from_request( $req, $person ); $person->update;

   my $message = [ 'User [_1] updated', $name ];

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
