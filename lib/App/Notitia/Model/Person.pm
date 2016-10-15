package App::Notitia::Model::Person;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( C_DIALOG EXCEPTION_CLASS FALSE
                                NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_action
                                p_fields p_list p_row p_table );
use App::Notitia::Util      qw( check_field_js dialog_anchor loc make_tip
                                management_link page_link_set
                                register_action_paths to_dt to_msg
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( create_token is_member throw );
use Class::Usul::Types      qw( ArrayRef );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

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

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_add_person_js = sub {
   my ($page, $name) = @_;

   my $opts = { domain => $name ? 'update' : 'insert', form => 'Person' };

   push @{ $page->{literal_js} },
      check_field_js( 'first_name',    $opts ),
      check_field_js( 'last_name',     $opts ),
      check_field_js( 'email_address', $opts ),
      check_field_js( 'postcode',      $opts );
};

my $_assert_not_self = sub {
   my ($person, $nok) = @_; $nok or undef $nok;

   $nok and $person->id and $nok == $person->id
        and throw 'Cannot set self as next of kin', level => 2;

   return $nok;
};

my $_bind_mugshot = sub {
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

   return { class => 'mugshot', href => $href,
            title => loc( $req, 'mugshot' ), type => 'image' };
};

my $_contact_links = sub {
   my ($req, $person) = @_; my @links; my $nok = $person->next_of_kin;

   push @links, { class => 'align-right', value => $person->home_phone };
   push @links, { class => 'align-right', value => $person->mobile_phone };
   push @links, { class => 'select-col align-center',
                  value => { name  => 'selected',
                             type  => 'checkbox',
                             value => $person->shortcode } };

   if (is_member 'person_manager', $req->session->roles) {
      push @links, { value => $nok ? $nok->label : NUL };
      push @links, { class => 'align-right',
                     value => $nok ? $nok->home_phone : NUL };
      push @links, { class => 'align-right',
                     value => $nok ? $nok->mobile_phone : NUL };
      push @links, { class => 'select-col align-center',
                     value => $nok ? { name  => 'selected',
                                       type  => 'checkbox',
                                       value => $nok->shortcode } : NUL };
   }

   return [ { value => $person->label }, @links ];
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

my $_maybe_find_person = sub {
   return $_[ 1 ] ? $_[ 0 ]->find_by_shortcode( $_[ 1 ] ) : Class::Null->new;
};

my $_people_headers = sub {
   my ($req, $params) = @_; my ($header, $max);

   my $role = $params->{role} // NUL; my $type = $params->{type} // NUL;

   if ($type eq 'contacts') {
      $header = 'contacts_heading';
      $max = is_member( 'person_manager', $req->session->roles) ? 7 : 3;
   }
   else {
      $header = 'people_heading';
      $max    = (is_member $role, qw( rider driver )) ? 4
              : (is_member $role, qw( controller rider driver )) ? 3
              : 2;
   }

   return [ map { { value => loc( $req, "${header}_${_}" ) } } 0 .. $max ];
};

my $_people_title = sub {
   my ($req, $role, $status, $type) = @_;

   my $k = $role   ? "${role}_list_link"
         : $type   ? "${type}_list_heading"
         : $status ? "${status}_people_list_link"
         :           'people_management_heading';

   return loc( $req, $k );
};

my $_person_ops_links = sub {
   my ($req, $page, $moniker, $person) = @_;

   my $scode = $person->shortcode;
   my $href = uri_for_action $req, "${moniker}/mugshot", [ $scode ];

   push @{ $page->{literal_js} //= [] },
      dialog_anchor( 'upload_mugshot', $href, {
         name    => 'mugshot_upload',
         title   => loc( $req, 'Mugshot Upload' ),
         useIcon => \1 } );

   my $mugshot = f_link 'mugshot', C_DIALOG, {
      action => 'upload', request => $req };

   my $actionp = "${moniker}/person";
   my $add_person = f_link 'person', uri_for_action( $req, $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };
   my $links = [ $mugshot, $add_person ];

   my $view_nok; if (my $nok = $person->next_of_kin) {
      $view_nok = f_link 'nok', uri_for_action( $req, $actionp, [ $nok ] ), {
         action => 'view', container_class => 'add-link', request => $req };
   }

   $view_nok and unshift @{ $links }, $view_nok;

   return $links;
};

my $_select_nav_link_name = sub {
   my $opts = { %{ $_[ 0 ] } };

   return
        $opts->{type} && $opts->{type} eq 'contacts' ? 'contacts_list'
      : $opts->{role} && $opts->{role} eq 'committee' ? 'committee_list'
      : $opts->{role} && $opts->{role} eq 'controller' ? 'controller_list'
      : $opts->{role} && $opts->{role} eq 'driver' ? 'driver_list'
      : $opts->{role} && $opts->{role} eq 'fund_raiser' ? 'fund_raiser_list'
      : $opts->{role} && $opts->{role} eq 'rider' ? 'rider_list'
      : $opts->{role} && $opts->{role} eq 'staff' ? 'staff_list'
      : $opts->{role} && $opts->{role} eq 'trustee' ? 'trustee_list'
      : $opts->{status} && $opts->{status} eq 'current' ? 'current_people_list'
      : 'people_list';
};

# Private methods
my $_bind_next_of_kin = sub {
   my ($self, $person, $disabled) = @_;

   my $opts   = { fields => { selected => $person->next_of_kin } };
   my $people = $self->schema->resultset( 'Person' )->list_all_people( $opts );

   $opts = { numify => TRUE, type => 'select',
             value  => [ [ NUL, NUL ], @{ $people } ] };
   $disabled and $opts->{disabled} = TRUE;

   return $opts;
};

my $_bind_view_nok = sub {
   my ($self, $req, $person, $disabled) = @_;

   $person->next_of_kin or return { value => NUL };

   my $actionp = $self->moniker.($disabled ? '/person_summary' : '/person');
   my $nok = $person->next_of_kin;

   return ;
};

my $_list_all_roles = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, NUL ], $type_rs->search_for_role_types->all ];
};

my $_lookup_coordinates = sub {
   my ($self, $person) = @_; $person->postcode or return;

   my $prog = $self->config->binsdir->catfile( 'notitia-schema' );
   my $scode = $person->shortcode;
   my $cmd = "${prog} geolocation ${scode}";
   my $rs = $self->schema->resultset( 'Job' );
   my $job = $rs->create( { command => $cmd, name => 'geolocation' } );

   $self->log->debug( "Coordinate lookup ${scode} geolocation-".$job->id );
   return;
};

my $_next_badge_id = sub {
   return $_[ 0 ]->schema->resultset( 'Person' )->next_badge_id;
};

my $_people_links = sub {
   my ($self, $req, $params, $person) = @_;

   my $moniker = $self->moniker; my $role = $params->{role};

   $params->{type} and $params->{type} eq 'contacts'
                   and return $_contact_links->( $req, $person );

   my @links; my $scode = $person->shortcode;

   my @paths = ( 'role/role' );

   $role and is_member $role, qw( controller driver rider )
      and push @paths, 'certs/certifications';

   unshift @paths, is_member( 'person_manager', $req->session->roles )
      ? "${moniker}/person" : "${moniker}/person_summary";

   $role and ($role eq 'rider' or $role eq 'driver')
         and push @paths, 'blots/endorsements';


   for my $actionp ( @paths ) {
      push @links, { value => management_link( $req, $actionp, $scode ) };
   }

   return [ { value => $person->label }, @links ];
};

my $_people_ops_links = sub {
   my ($self, $req, $page, $params, $pager) = @_;

   my $moniker = $self->moniker;
   my $actionp = "${moniker}/person";
   my $add_user = f_link 'person', uri_for_action( $req, $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   my $name = 'message_people';
   my $href = uri_for_action $req, "${moniker}/message", [], $params;
   my $message = $self->message_link( $req, $page, $href, $name );

   $actionp = "${moniker}/people";

   my $page_links = page_link_set $req, $actionp, [], $params, $pager;
   my $links = [ $message, $add_user ];

   $page_links and unshift @{ $links }, $page_links;

   return $links;
};

my $_update_person_from_request = sub {
   my ($self, $req, $schema, $person) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( active address badge_expires badge_id dob email_address
                     first_name home_phone joined last_name location
                     coordinates mobile_phone name notes password_expired
                     postcode region resigned subscription )) {
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
   $person->next_of_kin_id
      ( $_assert_not_self->( $person, $params->( 'next_of_kin', $opts ) ) );
   $person->badge_id and $person->badge_id eq 'next'
      and $person->badge_id( $self->$_next_badge_id );
   return;
};

my $_bind_person_fields = sub {
   my ($self, $req, $form, $person, $opts) = @_; $opts //= {};

   my $disabled  = $opts->{disabled} // FALSE;
   my $is_create = $opts->{action} && $opts->{action} eq 'create'
                 ? TRUE : FALSE;

   return
   [  mugshot          => $_bind_mugshot->( $self->config, $req, $person ),
      first_name       => { class    => 'narrow-field server',
                            disabled => $disabled },
      last_name        => { class    => 'narrow-field server',
                            disabled => $disabled },
      primary_role     => { class    => 'narrow-field',
                            disabled => $disabled,
                            type     => 'select',
                            value    => $person->shortcode
                                     ? $person->list_roles
                                     : $self->$_list_all_roles() },
      email_address    => { class    => 'standard-field server',
                            disabled => $disabled },
      address          => { disabled => $disabled },
      location         => { disabled => $disabled },
      postcode         => { class    => 'standard-field server',
                            disabled => $disabled },
      coordinates      => { disabled => $disabled },
      mobile_phone     => { disabled => $disabled },
      home_phone       => { disabled => $disabled },
      next_of_kin      => $self->$_bind_next_of_kin( $person, $disabled ),
      dob              => { disabled => $disabled, type => 'date' },
      joined           => { disabled => $disabled, type => 'date' },
      resigned         => { class    => 'standard-field clearable',
                            disabled => $disabled, type => 'date' },
      subscription     => { disabled => $disabled, type => 'date' },
      badge_id         => { disabled => $person->badge_id ? TRUE : $disabled,
                            tip      => make_tip( $req, 'badge_id_field_tip'),
                            value    => $is_create ? 'next' : undef },
      badge_expires    => { disabled => $disabled, type => 'date' },
      notes            => $disabled ? FALSE : {
         class         => 'standard-field autosize', type => 'textarea' },
      name             => { class    => 'standard-field',
                            disabled => $disabled, label => 'username',
                            tip => make_tip( $req, 'username_field_tip' ) },
      region           => { class => 'single-character', disabled => $disabled,
                            maxlength => 1, fieldsize => 1 },
      enable_2fa       => $is_create || $disabled ? FALSE : {
         checked       => $person->totp_secret ? TRUE : FALSE,
         label_class   => 'right', type => 'checkbox' },
      active           => $is_create || $disabled ? FALSE : {
         checked       => $person->active,
         label_class   => 'left', type => 'checkbox' },
      password_expired => $is_create || $disabled ? FALSE : {
         checked       => $person->password_expired,
         label_class   => 'right', type => 'checkbox' },
      ];
};

# Public methods
sub activate : Role(anon) {
   my ($self, $req) = @_; my ($location, $message);

   my $file = $req->uri_params->( 0 );
   my $path = $self->config->sessdir->catfile( $file );

   if ($path->exists and $path->is_file) {
      my $name   = $path->chomp->getline; $path->unlink;
      my $person = $self->find_by_shortcode( $name ); $person->activate;
      my $places = $self->config->places;

      $self->send_event( $req, "action:activate-person shortcode:${name}" );
      $location = uri_for_action $req, $places->{password}, [ $name ];
      $message  = [ to_msg '[_1] account activated', $person->label ];
   }
   else {
      $location = $req->base;
      $message  = [ 'Key [_1] unknown activation attempt', $file ];
   }

   return { redirect => { location => $location, message => $message } };
}

sub contacts : Role(address_viewer) Role(person_manager) Role(controller) {
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
      $self->$_lookup_coordinates( $person );
   };

   try   { $self->schema->txn_do( $create ) }
   catch { $self->rethrow_exception( $_, 'create', 'person', $person->name ) };

   my $id       = $self->create_person_email( $req, $person, $password );
   my $message  = 'action:create-person shortcode:'.$person->shortcode;

   $self->send_event( $req, $message );

   my $who      = $req->session->user_label;
   my $key      = '[_1] created by [_2] ref. [_3]';
   my $location = uri_for_action $req, $self->moniker.'/people';

   $message = [ to_msg $key, $person->label, $who, "send_message-${id}" ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $person   = $self->find_by_shortcode( $name );
   my $label    = $person->label;

   $name eq 'admin' and throw 'Cannot delete the admin user'; $person->delete;

   $self->send_event( $req, "action:delete-person shortcode:${name}" );

   my $who      = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/people';
   my $message  = [ to_msg '[_1] deleted by [_2]', $label, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub find_by_shortcode {
   return shift->schema->resultset( 'Person' )->find_by_shortcode( @_ );
}

sub message : Role(person_manager) {
   return $_[ 0 ]->message_stash( $_[ 1 ] );
}

sub message_create_action : Role(person_manager) {
   return $_[ 0 ]->message_create( $_[ 1 ], { action => 'people' } );
}

sub mugshot : Role(person_manager) {
   my ($self, $req) = @_;

   my $scode  = $req->uri_params->( 0 );
   my $stash  = $self->dialog_stash( $req );
   my $params = { name => $scode, type => 'mugshot' };
   my $places = $self->config->places;
   my $href   = uri_for_action $req, $places->{upload}, [], $params;

   $stash->{page}->{forms}->[ 0 ] = blank_form 'upload-file', $href;
   $self->components->{docs}->upload_dialog( $req, $stash->{page} );

   return $stash;
}

sub person : Role(person_manager) {
   my ($self, $req) = @_; my $people;

   my $moniker    =  $self->moniker;
   my $name       =  $req->uri_params->( 0, { optional => TRUE } );
   my $href       =  uri_for_action $req, "${moniker}/person", [ $name ];
   my $form       =  blank_form 'person-admin', $href;
   my $action     =  $name ? 'update' : 'create';
   my $page       =  {
      first_field => 'first_name',
      forms       => [ $form ],
      title       => loc $req,  "person_${action}_heading" };
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $opts       =  { action => $action };
   my $fields     =  $self->$_bind_person_fields( $req, $form, $person, $opts );
   my $links      =  $_person_ops_links->( $req, $page, $moniker, $person );
   my $args       =  [ 'person', $person->label ];

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_fields $form, $self->schema, 'Person', $person, $fields;

   p_action $form, $action, $args, { request => $req };

   $name and p_action $form, 'delete', $args, { request => $req };

   $_add_person_js->( $page, $name ),

   return $self->get_stash( $req, $page );
}

sub person_summary : Role(person_manager) Role(address_viewer)
                     Role(training_manager) {
   my ($self, $req) = @_; my $people;

   my $name       =  $req->uri_params->( 0 );
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $_maybe_find_person->( $person_rs, $name );
   my $form       =  blank_form { class => 'standard-form' };
   my $opts       =  { disabled => TRUE };
   my $fields     =  $self->$_bind_person_fields( $req, $form, $person, $opts );
   my $page       =  {
      first_field => 'first_name',
      forms       => [ $form ],
      title       => loc( $req, 'person_summary_heading' ), };

   p_fields $form, $self->schema, 'Person', $person, $fields;

   return $self->get_stash( $req, $page );
}

sub people : Role(administrator) Role(person_manager) Role(address_viewer) {
   my ($self, $req, $type) = @_;

   my $actionp =  $self->moniker.'/people';
   my $params  =  $req->query_params->( { optional => TRUE } );
   my $role    =  $params->{role  };
   my $status  =  $params->{status};

   $type and $params->{type} = $type; $type = $params->{type} || NUL;

   my $opts    =  { page   => delete $params->{page} // 1,
                    role   => $role,
                    rows   => $req->session->rows_per_page,
                    status => $status,
                    type   => $type, };
   my $href    =  uri_for_action $req, $actionp, [], $params;
   my $form    =  blank_form 'people', $href, {
      class    => 'wider-table', id => 'people' };
   my $page    =  {
      forms    => [ $form ],
      selected => $_select_nav_link_name->( $opts ),
      title    => $_people_title->( $req, $role, $status, $type ), };
   my $rs      =  $self->schema->resultset( 'Person' );
   my $people  =  $rs->search_for_people( $opts );
   my $links   =  $self->$_people_ops_links
      ( $req, $page, $params, $people->pager );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, { headers => $_people_headers->( $req, $params )};

   $type eq 'contacts' and is_member( 'person_manager', $req->session->roles )
      and $table->{class} = 'smaller-table';

   p_row $table, [ map { $self->$_people_links( $req, $params, $_ ) }
                   $people->all ];

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub update_person_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $scode  = $req->uri_params->( 0 );
   my $person = $self->find_by_shortcode( $scode );
   my $pcode  = $person->postcode // NUL;
   my $label  = $person->label;

   $self->$_update_person_from_request( $req, $self->schema, $person );

   try {
      $person->update;
      $pcode ne $person->postcode and $self->$_lookup_coordinates( $person );
   }
   catch { $self->rethrow_exception( $_, 'update', 'person', $label ) };

   $self->send_event( $req, "action:update-person shortcode:${scode}" );

   my $who      = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/people';
   my $message  = [ to_msg '[_1] updated by [_2]', $label, $who ];

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
