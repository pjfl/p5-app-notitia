package App::Notitia::Model::Person;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( bind bind_fields button check_field_js
                                create_link delete_button dialog_anchor
                                field_options loc mail_domain make_tip
                                management_link operation_links
                                register_action_paths save_button table_link
                                to_dt uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_arrayref is_member throw );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);
with    q(App::Notitia::Role::Messaging);

# Public attributes
has '+moniker' => default => 'person';

register_action_paths
   'person/activate'       => 'person-activate',
   'person/contacts'       => 'contacts',
   'person/message'        => 'message-people',
   'person/mugshot'        => 'mugshot',
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
   my $name = shift;
   my $opts = { domain => $name ? 'update' : 'insert', form => 'Person' };

   return [ check_field_js( 'first_name',    $opts ),
            check_field_js( 'last_name',     $opts ),
            check_field_js( 'email_address', $opts ),
            check_field_js( 'postcode',      $opts ), ];
};

my $_assert_not_self = sub {
   my ($person, $nok) = @_; $nok or undef $nok;

   $nok and $person->id and $nok == $person->id
        and throw 'Cannot set self as next of kin', level => 2;

   return $nok;
};

my $_confirm_mugshot_button = sub {
   return button $_[ 0 ],
      { class => 'right-last', label => 'confirm', value => 'mugshot_create' };
};

my $_contact_links = sub {
   my ($req, $person) = @_; my @links;

   push @links, { value => $person->home_phone };
   push @links, { value => $person->mobile_phone };
   push @links, { value => $person->next_of_kin
                         ? $person->next_of_kin->label : NUL };
   push @links, { value => $person->next_of_kin
                         ? $person->next_of_kin->home_phone : NUL };
   push @links, { value => $person->next_of_kin
                         ? $person->next_of_kin->mobile_phone : NUL };

   return @links;
};

my $_copy_element_value = sub {
   return [ "\$( 'upload-btn' ).addEvent( 'change', function( ev ) {",
            "   ev.stop(); \$( 'upload-path' ).value = this.value } )", ];
};

my $_maybe_find_person = sub {
   return $_[ 1 ] ? $_[ 0 ]->find_by_shortcode( $_[ 1 ] ) : Class::Null->new;
};

my $_next_of_kin_list = sub {
   my ($people, $disabled) = @_; my $opts = { numify => TRUE };

   $disabled and $opts->{disabled} = TRUE;

   return bind 'next_of_kin', [ [ NUL, NUL ], @{ $people } ], $opts;
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
   my ($req, $tuple, $params) = @_; my $role = $params->{role};

   $params->{type} and $params->{type} eq 'contacts'
                   and return $_contact_links->( $req, $tuple->[ 1 ] );

   my $scode = $tuple->[ 1 ]->shortcode;
   my $k     = $role ? "${role}_${scode}" : $scode;
   my $links = $_people_links_cache->{ $k }; $links and return @{ $links };
   my @paths = ( 'person/person', 'role/role', 'certs/certifications' );

   $role and ($role eq 'bike_rider' or $role eq 'driver')
         and push @paths, 'blots/endorsements';

   $links = [];

   for my $actionp ( @paths ) {
      push @{ $links }, { value => management_link( $req, $actionp, $scode ) };
   }

   $_people_links_cache->{ $k } = $links;

   return @{ $links };
};

my $_person_mugshot = sub {
   my ($conf, $req, $person) = @_;

   my $uri = $conf->assets.'/mugshot/'; my $href;

   if ($person->shortcode) {
      my $assets = $conf->assetdir->catdir( 'mugshot' );

      for my $extn (qw( .gif .jpeg .jpg .png )) {
         my $path = $assets->catfile( $person->shortcode.$extn );

         $path->exists
            and $href = $req->uri_for( $uri.$person->shortcode.$extn )
            and last;
      }
   }

   $href //= $req->uri_for( $uri.'nomugshot.png' );

   return { class => 'mugshot', href => $href, title => loc( $req, 'mugshot' )};
};

my $_person_ops_links = sub {
   my ($req, $page, $actionp, $scode) = @_;

   my $add_person = create_link $req, $actionp, 'person',
                                { container_class => 'add-link' };
   my $mugshot    = table_link  $req, 'mugshot',
                                loc( $req, 'mugshot_upload_link' ),
                                loc( $req, 'mugshot_upload_tip' );
   my $href       = uri_for_action $req, 'person/mugshot', [ $scode ];

   push @{ $page->{literal_js} //= [] },
      dialog_anchor( 'mugshot', $href, {
         name    => 'mugshot_upload',
         title   => loc( $req, 'Mugshot Upload' ),
         useIcon => \1 } );

   return operation_links [ $mugshot, $add_person ];
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
         last_name    => $person->last_name,
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

my $_people_ops_links = sub {
   my ($self, $req, $page, $params) = @_;

   $params->{name} = 'message_people';

   my $moniker  = $self->moniker;
   my $actionp  = "${moniker}/message";
   my $message  = $self->message_link( $req, $page, $actionp, $params );
   my $opts     = { container_class => 'add-link' };
   my $add_user = create_link $req, "${moniker}/person", 'person', $opts;

   return operation_links [ $message, $add_user ];
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

      length $v and is_member $attr, [ qw( dob joined resigned subscription ) ]
         and $v = to_dt $v;

      $person->$attr( $v );
   }

   $person->resigned and $person->active( FALSE );
   $person->name( $params->( 'username', $opts ) );
   $person->next_of_kin_id
      ( $_assert_not_self->( $person, $params->( 'next_of_kin', $opts ) ) );

   return;
};

my $_bind_person_fields = sub {
   my ($self, $req, $person, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;
   my $map      = {
      active           => { checked  => $person->active,
                            disabled => $disabled },
      address          => { disabled => $disabled },
      dob              => { disabled => $disabled },
      email_address    => { class    => 'standard-field server',
                            disabled => $disabled },
      first_name       => { class    => 'narrow-field server',
                            disabled => $disabled },
      home_phone       => { disabled => $disabled },
      joined           => { disabled => $disabled },
      last_name        => { class    => 'narrow-field server',
                            disabled => $disabled },
      mobile_phone     => { disabled => $disabled },
      notes            => { class    => 'standard-field autosize',
                            disabled => $disabled },
      password_expired => { checked  => $person->password_expired,
                            container_class => 'right-last',
                            disabled => $disabled },
      postcode         => { class    => 'standard-field server',
                            disabled => $disabled },
      resigned         => { class    => 'standard-field clearable',
                            disabled => $disabled },
      subscription     => { disabled => $disabled },
   };

   my $fields = bind_fields $self->schema, $person, $map, 'Person';

   $opts = { class => 'narrow-field', disabled => $disabled };
   $fields->{primary_role} = $person->shortcode
      ? bind 'primary_role', $person->list_roles, $opts,
      : bind 'primary_role', $self->$_list_all_roles(), $opts;
   $opts = { fields => { selected => $person->next_of_kin } };

   my $people = $self->schema->resultset( 'Person' )->list_all_people( $opts );

   $fields->{next_of_kin} = $_next_of_kin_list->( $people, $disabled );
   $fields->{mugshot} = $_person_mugshot->( $self->config, $req, $person );
   return $fields;
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
   catch { $self->rethrow_exception( $_, 'create', 'person', $person->name ) };

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

sub message : Role(person_manager) {
   my ($self, $req) = @_;

   my $opts = { action => 'message-people', layout => 'message-people'};

   return $self->message_stash( $req, $opts );
}

sub message_create_action : Role(person_manager) {
   return $_[ 0 ]->message_create( $_[ 1 ], { action => 'people' } );
}

sub mugshot : Role(person_manager) {
   my ($self, $req) = @_;

   my $scode  = $req->uri_params->( 0 );
   my $stash  = $self->dialog_stash( $req, 'upload-file' );
   my $params = { name => $scode, type => 'mugshot' };
   my $page   = $stash->{page};

   $page->{fields}->{href} = uri_for_action $req, 'docs/upload', [], $params;
   $stash->{page}->{literal_js} = $_copy_element_value->();

   return $stash;
}

sub person : Role(person_manager) {
   my ($self, $req) = @_; my $people;

   my $name       =  $req->uri_params->( 0, { optional => TRUE } );
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $page       =  {
      fields      => $self->$_bind_person_fields( $req, $person ),
      first_field => 'first_name',
      literal_js  => $_add_person_js->( $name ),
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
      $fields->{user_href} = uri_for_action $req, $actionp, [ $name ];
      $fields->{delete} = delete_button $req, $name, { type => 'person' };
      $fields->{links} = $_person_ops_links->( $req, $page, $actionp, $name );
   }

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
      fields      => $self->$_bind_person_fields( $req, $person, $opts ),
      first_field => 'first_name',
      template    => [ 'contents', 'person' ],
      title       => loc( $req, 'person_summary_heading' ), };
   my $fields     =  $page->{fields};

   $opts = field_options $self->schema, 'Person', 'name', $opts;
   $fields->{username} = bind 'username', $person->name, $opts;
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
         headers => $_people_headers->( $req, $params ),
         rows    => [], },
      template   => [ 'contents', 'table' ],
      title      => loc( $req, $title_key ), };
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $fields    =  $page->{fields};
   my $rows      =  $fields->{rows};
   my $opts      =  {};

   $fields->{links} = $self->$_people_ops_links( $req, $page, $params );
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
   catch { $self->rethrow_exception( $_, 'update', 'person', $label ) };

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
