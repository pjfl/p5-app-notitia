package App::Notitia::Model::Person;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( bind bind_fields button check_field_server
                                create_link delete_button field_options loc
                                mail_domain make_tip management_link
                                register_action_paths save_button
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_arrayref is_member throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);

# Public attributes
has '+moniker' => default => 'person';

register_action_paths
   'person/activate'       => 'person-activate',
   'person/contacts'       => 'contacts',
   'person/people'         => 'people',
   'person/person'         => 'person',
   'person/person_summary' => 'person-summary';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav }->{list    }   = $self->admin_navigation_links( $req );
   $stash->{page}->{location} //= 'admin';

   return $stash;
};

# Private class attributes
my $_people_links_cache = {};

# Private functions
my $_add_person_js = sub {
   my $opts = { domain => 'schedule', form => 'Person' };

   return [ check_field_server( 'first_name',    $opts ),
            check_field_server( 'last_name',     $opts ),
            check_field_server( 'email_address', $opts ),
            check_field_server( 'postcode',      $opts ), ];
};

my $_bind_person_fields = sub {
   my ($schema, $person, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;
   my $map      = {
      active           => { checked  => $person->active, disabled => $disabled,
                            nobreak  => TRUE, },
      address          => { disabled => $disabled },
      dob              => { disabled => $disabled },
      email_address    => { class    => 'standard-field server',
                            disabled => $disabled },
      first_name       => { class    => 'standard-field server',
                            disabled => $disabled },
      home_phone       => { disabled => $disabled },
      joined           => { disabled => $disabled },
      last_name        => { class    => 'standard-field server',
                            disabled => $disabled },
      mobile_phone     => { disabled => $disabled },
      notes            => { class    => 'standard-field autosize',
                            disabled => $disabled },
      password_expired => { checked  => $person->password_expired,
                            container_class => 'right-last',
                            disabled => $disabled },
      postcode         => { class    => 'standard-field server',
                            disabled => $disabled },
      resigned         => { disabled => $disabled },
      subscription     => { disabled => $disabled },
   };

   return bind_fields $schema, $person, $map, 'Person';
};

my $_contact_links = sub {
   my ($req, $person) = @_; my $links = [];

   push @{ $links }, { value => $person->home_phone };
   push @{ $links }, { value => $person->mobile_phone };
   push @{ $links }, { value => $person->next_of_kin
                              ? $person->next_of_kin->label : NUL };
   push @{ $links }, { value => $person->next_of_kin
                              ? $person->next_of_kin->home_phone : NUL };
   push @{ $links }, { value => $person->next_of_kin
                              ? $person->next_of_kin->mobile_phone : NUL };

   return @{ $links };
};

my $_assert_not_self = sub {
   my ($person, $nok) = @_; $nok or undef $nok;

   $nok and $person->id and $nok == $person->id
        and throw 'Cannot set self as next of kin',
                  level => 2, rv => HTTP_EXPECTATION_FAILED;

   return $nok;
};

my $_maybe_find_person = sub {
   return $_[ 1 ] ? $_[ 0 ]->find_by_shortcode( $_[ 1 ] ) : Class::Null->new;
};

my $_next_of_kin_list = sub {
   return bind 'next_of_kin', [ [ NUL, NUL ], @{ $_[ 0 ] } ], { numify => TRUE};
};

my $_people_headers = sub {
   my ($req, $params) = @_; my ($header, $max);

   my $role = $params->{role} // NUL; my $type = $params->{type} // NUL;

   if ($type eq 'contacts') { $header = 'contacts_heading'; $max = 5 }
   else {
      $header = 'people_heading';
      $max    = ($role eq 'bike_rider' || $role eq 'driver') ? 4 : 3;
   }

   return [ map { { value => loc( $req, "${header}_${_}" ) } } 0 .. $max ];
};

my $_people_links = sub {
   my ($req, $person, $params) = @_; my $role = $params->{role};

   $params->{type} and $params->{type} eq 'contacts'
                   and return $_contact_links->( $req, $person->[ 1 ] );

   my $scode = $person->[ 1 ]->shortcode;
   my $k     = $role ? "${role}_${scode}" : $scode;
   my $links = $_people_links_cache->{ $k }; $links and return @{ $links };

   $links = []; my @paths = ( 'person/person', 'role/role', 'certs/certifications' );

   $role and ($role eq 'bike_rider' or $role eq 'driver')
         and push @paths, 'blots/endorsements';

   for my $actionp ( @paths ) {
      push @{ $links }, { value => management_link( $req, $actionp, $scode ) };
   }

   $_people_links_cache->{ $k } = $links;

   return @{ $links };
};

# Private methods
my $_create_person_email = sub {
   my ($self, $req, $person, $password) = @_;

   my $conf    = $self->config;
   my $key     = substr create_token, 0, 32;
   my $opts    = { params => [ $conf->title ], no_quote_bind_values => TRUE };
   my $subject = loc $req, 'Account activation for [_1]', $opts;
   my $href    = uri_for_action $req, $self->moniker.'/activate', [ $key ];
   my $post    = {
      attributes      => {
         charset      => $conf->encoding,
         content_type => 'text/html', },
      from            => $conf->title.'@'.mail_domain(),
      stash           => {
         app_name     => $conf->title,
         first_name   => $person->first_name,
         link         => $href,
         password     => $password,
         title        => $subject,
         username     => $person->name, },
      subject         => $subject,
      template        => 'user_email',
      to              => $person->email_address, };

   $conf->sessdir->catfile( $key )->println( $person->shortcode );

   my $r = $self->send_email( $post );
   my ($id) = $r =~ m{ ^ OK \s+ id= (.+) $ }msx; chomp $id;

   $self->log->info( loc( $req, 'New user email sent - [_1]', [ $id ] ) );

   return;
};

my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->list_role_types->all ];
};

my $_update_person_from_request = sub {
   my ($self, $req, $schema, $person) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( active address dob email_address first_name home_phone
                     joined last_name mobile_phone notes password_expired
                     postcode resigned subscription )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts );

      not defined $v and is_member $attr, [ qw( active password_expired ) ]
          and $v = FALSE;

      defined $v or next; $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      # No tz and 1/1/1970 is the last day in 69
      length $v and is_member $attr, [ qw( dob joined resigned subscription ) ]
         and $v = $self->to_dt( $v );

      $person->$attr( $v );
   }

   $person->name( $params->( 'username', $opts ) );
   $person->next_of_kin_id
      ( $_assert_not_self->( $person, $params->( 'next_of_kin', $opts ) ) );

   return;
};

# Public methods
sub activate : Role(anon) {
   my ($self, $req) = @_; my ($location, $message);

   my $file = $req->uri_params->( 0 );
   my $path = $self->config->sessdir->catfile( $file );

   if ($path->exists and $path->is_file) {
      my $name   = $path->chomp->getline; $path->unlink;
      my $person = $self->find_by_shortcode( $name ); $person->activate;

      $location = uri_for_action $req, 'user/change_password', [ $name ];
      $message  = [ 'Person [_1] account activated', $person->label ];
   }
   else {
      $location = $req->base;
      $message  = [ 'Key [_1] unknown activation attempt', $file ];
   }

   return { redirect => { location => $location, message => $message } };
}

sub contacts : Role(person_manager) Role(address_viewer) {
   my ($self, $req) = @_; return $self->people( $req, 'contacts' );
}

sub create_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $person = $self->schema->resultset( 'Person' )->new_result( {} );

   $self->$_update_person_from_request( $req, $self->schema, $person );

   my $role = $req->body_params->( 'primary_role', { optional => TRUE } );

   $person->password( my $password = substr create_token, 0, 12 );
   $person->password_expired( TRUE );

   my $coderef = sub {
      $person->insert; $role and $person->add_member_to( $role );
   };

   try   { $self->schema->txn_do( $coderef ) }
   catch {
      $self->log->error( $_ ); throw 'Failed to create [_1]', [ $person->name ];
   };

   $self->config->no_user_email
      or $self->$_create_person_email( $req, $person, $password );

   my $location = uri_for_action $req, $self->moniker.'/people';
   my $message  = [ '[_1] created by [_2]', $person->label, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->find_by_shortcode( $name );
   my $label    = $person->label; $person->delete;
   my $location = uri_for_action $req, $self->moniker.'/people';
   my $message  = [ 'Person [_1] deleted by [_2]', $label, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub find_by_shortcode {
   return shift->schema->resultset( 'Person' )->find_by_shortcode( @_ );
}

sub person : Role(person_manager) {
   my ($self, $req) = @_; my $people;

   my $name       =  $req->uri_params->( 0, { optional => TRUE } );
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $page       =  {
      fields      => $_bind_person_fields->( $self->schema, $person ),
      first_field => 'first_name',
      literal_js  => $_add_person_js->(),
      template    => [ 'contents', 'person' ],
      title       => loc( $req, $name ? 'person_edit_heading'
                                      : 'person_create_heading' ), };
   my $fields     =  $page->{fields};
   my $actionp    =  $self->moniker.'/person';
   my $opts       =  field_options $self->schema, 'Person', 'name',
                        { class => 'standard-field',
                          tip   => make_tip( $req, 'username_field_tip' ) };

   $fields->{username} = bind 'username', $person->name, $opts;

   if ($name) {
      my $opts = { fields => { selected => $person->next_of_kin } };

      $people  = $person_rs->list_all_people( $opts );
      $fields->{user_href   } = uri_for_action $req, $actionp, [ $name ];
      $fields->{delete      } = delete_button $req, $name, { type => 'person' };
      $fields->{primary_role} = bind 'primary_role', $person->list_roles;
      $fields->{add         } = create_link $req, $actionp, 'person',
                                { container_class => 'add-link right' };
   }
   else {
      $people  = $person_rs->list_all_people();
      $fields->{primary_role} = bind 'primary_role', $self->$_list_all_roles();
   }

   $fields->{next_of_kin} = $_next_of_kin_list->( $people );
   $fields->{save} = save_button $req, $name, { type => 'person' };

   return $self->get_stash( $req, $page );
}

sub person_summary : Role(person_manager) Role(address_viewer) {
   my ($self, $req) = @_; my $people;

   my $name       =  $req->uri_params->( 0 );
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $opts       =  { class => 'standard-field', disabled => TRUE };
   my $page       =  {
      fields      => $_bind_person_fields->( $self->schema, $person, $opts ),
      first_field => 'first_name',
      template    => [ 'contents', 'person' ],
      title       => loc( $req, 'person_summary_heading' ), };
   my $fields     =  $page->{fields};

   $opts    = field_options $self->schema, 'Person', 'name', $opts;
   $fields->{username    } = bind 'username', $person->name, $opts;
   $opts    = { fields => { selected => $person->next_of_kin } };
   $people  = $person_rs->list_all_people( $opts );
   $fields->{next_of_kin } = $_next_of_kin_list->( $people );
   $fields->{primary_role} = bind 'primary_role', $person->list_roles;
   delete $fields->{notes};

   return $self->get_stash( $req, $page );
}

sub people : Role(any) {
   my ($self, $req, $type) = @_;

   my $params    =  $req->query_params->( { optional => TRUE } );
   my $role      =  $params->{role  } // NUL;
   my $status    =  $params->{status} // NUL;

   $type //= NUL; delete $params->{type}; $type and $params->{type} = $type;

   my $title_key =  $role   ? "${role}_list_link"
                 :  $type   ? "${type}_list_heading"
                 :  $status ? "${status}_people_list_link"
                 :            'people_management_heading';
   my $page      =  {
      fields     => {
         add     => create_link( $req, $self->moniker.'/person', 'person' ),
         headers => $_people_headers->( $req, $params ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, $title_key ), };
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $rows      =  $page->{fields}->{rows};
   my $opts      =  {};

   $status eq 'current'  and $opts->{current } = TRUE;
   $type   eq 'contacts' and $opts->{prefetch} = [ 'next_of_kin' ]
      and $opts->{columns} = [ 'home_phone', 'mobile_phone' ]
      and $page->{fields}->{class} = 'smaller-table';

   my $people = $role ? $person_rs->list_people( $role, $opts )
                      : $person_rs->list_all_people( $opts );

   for my $person (@{ $people }) {
      push @{ $rows }, [ { value => $person->[ 0 ]  },
                         $_people_links->( $req, $person, $params ) ];
   }

   return $self->get_stash( $req, $page );
}

sub update_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name   = $req->uri_params->( 0 );
   my $person = $self->find_by_shortcode( $name );
   my $label  = $person->label;

   $self->$_update_person_from_request( $req, $self->schema, $person );

   try   { $person->update }
   catch { $self->log->error( $_ ); throw 'Failed to update [_1]', [ $name ] };

   my $location = uri_for_action $req, $self->moniker.'/people';
   my $message  = [ '[_1] updated by [_2]', $label, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Person - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Person;
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
