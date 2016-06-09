package App::Notitia::Model::Person;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( bind bind_fields button check_field_js
                                create_link delete_button dialog_anchor
                                field_options loc make_tip
                                management_link operation_links page_link_set
                                register_action_paths save_button table_link
                                to_dt to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_arrayref is_member throw );
use Class::Usul::Types      qw( ArrayRef );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);
with    q(App::Notitia::Role::Messaging);

# Public attributes
has '+moniker' => default => 'person';

has 'max_badge_id' => is => 'ro', isa => ArrayRef, builder => sub { [ 0, 0 ] };

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
   my ($req, $person) = @_; my @links; my $nok = $person->next_of_kin;

   push @links, { class => 'align-right', value => $person->home_phone };
   push @links, { class => 'align-right', value => $person->mobile_phone };
   push @links, { class => 'align-center',
                  value => { name  => 'selected',
                             type  => 'checkbox',
                             value => $person->shortcode } };
   push @links, { value => $nok ? $nok->label : NUL };
   push @links, { class => 'align-right',
                  value => $nok ? $nok->home_phone : NUL };
   push @links, { class => 'align-right',
                  value => $nok ? $nok->mobile_phone : NUL };
   push @links, { class => 'align-center',
                  value => $nok ? { name  => 'selected',
                                    type  => 'checkbox',
                                    value => $nok->shortcode } : NUL };

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

   if ($type eq 'contacts') { $header = 'contacts_heading'; $max = 7 }
   else {
      $header = 'people_heading';
      $max    = ($role eq 'bike_rider' || $role eq 'driver') ? 4 : 3;
   }

   return [ map { { value => loc( $req, "${header}_${_}" ) } } 0 .. $max ];
};

my $_people_links = sub {
   my ($req, $person, $params) = @_; my $role = $params->{role};

   $params->{type} and $params->{type} eq 'contacts'
                   and return $_contact_links->( $req, $person );

   my $scode = $person->shortcode;
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

my $_people_title = sub {
   my ($req, $role, $status, $type) = @_;

   my $k = $role   ? "${role}_list_link"
         : $type   ? "${type}_list_heading"
         : $status ? "${status}_people_list_link"
         :           'people_management_heading';

   return loc( $req, $k );
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
my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search_for_role_types->all ];
};

my $_next_badge_id = sub {
   return $_[ 0 ]->schema->resultset( 'Person' )->next_badge_id;
};

my $_people_ops_links = sub {
   my ($self, $req, $page, $params, $pager) = @_;

   my $moniker    = $self->moniker;
   my $add_user   = create_link $req, "${moniker}/person",
                                'person', { container_class => 'add-link' };
   my $name       = 'message_people';
   my $href       = uri_for_action $req, "${moniker}/message", [], $params;
   my $message    = $self->message_link( $req, $page, $href, $name );
   my $links      = [ $message, $add_user ];
   my $actionp    = "${moniker}/people";
   my $page_links = page_link_set $req, $actionp, [], $params, $pager;

   $page_links and unshift @{ $links }, $page_links;

   return operation_links $links;
};

my $_update_person_from_request = sub {
   my ($self, $req, $schema, $person) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( active address badge_expires badge_id dob email_address
                     first_name home_phone joined last_name mobile_phone notes
                     password_expired postcode resigned subscription )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts );

      not defined $v and is_member $attr, [ qw( active password_expired ) ]
          and $v = FALSE;

      $attr eq 'badge_id' and defined $v and not length $v and undef $v;

      defined $v or next; $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      length $v and is_member $attr,
         [ qw( badge_expires dob joined resigned subscription ) ]
         and $v = to_dt $v;

      $person->$attr( $v );
   }

   $person->set_totp_secret( $params->( 'enable_2fa', $opts ) ? TRUE : FALSE );
   $person->resigned and $person->active( FALSE );
   $person->name( $params->( 'username', $opts ) );
   $person->next_of_kin_id
      ( $_assert_not_self->( $person, $params->( 'next_of_kin', $opts ) ) );
   $person->badge_id and $person->badge_id eq 'next'
      and $person->badge_id( $self->$_next_badge_id );
   return;
};

my $_bind_person_fields = sub {
   my ($self, $req, $person, $opts) = @_; $opts //= {};

   my $disabled = $opts->{disabled} // FALSE;
   my $map      = {
      active           => { checked  => $person->active,
                            disabled => $disabled },
      address          => { disabled => $disabled },
      badge_expires    => { disabled => $disabled },
      badge_id         => { disabled => $person->badge_id ? TRUE : $disabled,
                            tip      => make_tip( $req, 'badge_id_field_tip' )},
      dob              => { disabled => $disabled },
      email_address    => { class    => 'standard-field server',
                            disabled => $disabled },
      enable_2fa       => { checked  => $person->totp_secret ? TRUE : FALSE,
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
                            label_class => 'right-last',
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
      $message  = [ to_msg '[_1] account activated', $person->label ];
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

   my $create = sub {
      $person->insert; $role and $person->add_member_to( $role );
   };

   try   { $self->schema->txn_do( $create ) }
   catch { $self->rethrow_exception( $_, 'create', 'person', $person->name ) };

   my $who      = $req->session->user_label;
   my $key      = '[_1] created by [_2] ref. [_3]';
   my $id       = $self->create_person_email( $req, $person, $password );
   my $message  = [ to_msg $key, $person->label, $who, "send_message-${id}" ];
   my $location = uri_for_action $req, $self->moniker.'/people';

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->find_by_shortcode( $name );
   my $label    = $person->label; $person->delete;
   my $who      = $req->session->user_label;
   my $message  = [ to_msg '[_1] deleted by [_2]', $label, $who ];
   my $location = uri_for_action $req, $self->moniker.'/people';

   return { redirect => { location => $location, message => $message } };
}

sub find_by_shortcode {
   return shift->schema->resultset( 'Person' )->find_by_shortcode( @_ );
}

sub message : Role(person_manager) {
   my ($self, $req) = @_;

   return $self->message_stash( $req, { layout => 'message-people'} );
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
   $page->{literal_js} = $_copy_element_value->();

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
   else { $fields->{badge_id}->{value} = 'next' }

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
   my $role      =  $params->{role  };
   my $status    =  $params->{status};

   $type and $params->{type} = $type; $type = $params->{type} || NUL;

   my $opts      =  { page   => delete $params->{page} // 1,
                      role   => $role,
                      rows   => $req->session->rows_per_page,
                      status => $status,
                      type   => $type, };
   my $actionp   =  $self->moniker.'/people';
   my $person_rs =  $self->schema->resultset( 'Person' );
   my $people    =  $person_rs->search_for_people( $opts );
   my $page      =  {
      fields     => {
         headers => $_people_headers->( $req, $params ),
         rows    => [], },
      form       => {
         name    => 'people',
         href    => uri_for_action( $req, $actionp, [], $params ) },
      template   => [ 'contents', 'table' ],
      title      => $_people_title->( $req, $role, $status, $type ), };
   my $fields    =  $page->{fields};
   my $rows      =  $fields->{rows};

   $fields->{links}
      = $self->$_people_ops_links( $req, $page, $params, $people->pager );
   $type eq 'contacts' and $fields->{class} = 'smaller-table';

   for my $person ($people->all) {
      push @{ $rows }, [ { value => $person->label  },
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

   my $who      = $req->session->user_label;
   my $message  = [ to_msg '[_1] updated by [_2]', $label, $who ];
   my $location = uri_for_action $req, $self->moniker.'/people';

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
