package App::Notitia::Model::Incident;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link f_tag p_action p_button
                                p_container p_fields p_link p_list p_row
                                p_select p_table p_textfield );
use App::Notitia::Util      qw( check_field_js js_window_config locm make_tip
                                page_link_set register_action_paths to_dt
                                to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'inc';

register_action_paths
   'inc/incident_party' => 'incident/*/parties',
   'inc/incident'       => 'incident',
   'inc/incidents'      => 'incidents';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'calls';
   $stash->{navigation} = $self->call_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_add_incident_js = sub {
   my ($page, $name) = @_;

   my $opts = { domain => $name ? 'update' : 'insert', form => 'Incident' };

   push @{ $page->{literal_js} },
      check_field_js( 'reporter', $opts ),
      check_field_js( 'title', $opts );

   return;
};

my $_category_tuple = sub {
   my ($selected, $category) = @_;

   my $opts = { selected => $selected == $category->id ? TRUE : FALSE };

   return [ $category->name, $category->id, $opts ];
};

my $_incidents_headers = sub {
   my $req = shift; my $header = 'incidents_heading';

   return [ map { { value => locm $req, "${header}_${_}" } } 0 .. 2 ];
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

my $_person_tuple = sub {
   my ($selected, $person) = @_;

   my $opts = { selected => $selected == $person->id ? TRUE : FALSE };

   return [ $person->label, $person->id, $opts ];
};

my $_bind_call_category = sub {
   my ($categories, $incident) = @_;

   my $selected = $incident->category_id; my $other;

   return [ [ NUL, undef ],
            (map  { $_category_tuple->( $selected, $_ ) }
             grep { $_->name eq 'other' and $other = $_; $_->name ne 'other' }
             $categories->all), $_category_tuple->( $selected, $other ) ];
};

my $_subtract = sub {
   return [ grep { not is_member $_->[ 1 ], [ map { $_->[ 1 ] } @{ $_[ 1 ] } ] }
                @{ $_[ 0 ] } ];
};

# Private methods
my $_bind_committee_member = sub {
   my ($self, $incident) = @_;

   my $selected = $incident->committee_member_id || 0;
   my $rs = $self->schema->resultset( 'Person' );
   my $opts = { role => 'committee', status => 'current', };

   return [ [ NUL, undef ],
            map { $_person_tuple->( $selected, $_ ) }
            $rs->search_for_people( $opts ) ];
};

my $_bind_incident_fields = sub {
   my ($self, $req, $page, $incident, $opts) = @_; $opts //= {};

   my $schema = $self->schema;
   my $disabled = $opts->{disabled} // FALSE;
   my $type_rs = $schema->resultset( 'Type' );
   my $categories = $type_rs->search_for_call_categories;
   my $other_type_id = $type_rs->find_type_by( 'other', 'call_category' )->id;

   push @{ $page->{literal_js} }, js_window_config 'category', 'change',
      'showIfNeeded', [ 'category', $other_type_id, 'category_other_field' ];

   return
      [  controller     => $incident->id ? {
            disabled    => TRUE,
            value       => $incident->controller->label } : FALSE,
         raised         => $incident->id ? {
            disabled    => TRUE, value => $incident->raised_label( $req ) }
                         : FALSE,
         title          => {
            class       => 'standard-field server',
            disabled    => $disabled, label => 'incident_title' },
         reporter       => { class => 'standard-field server',
                             disabled => $disabled },
         reporter_phone => { disabled => $disabled },
         category_id    => {
            class       => 'standard-field windows',
            disabled    => $disabled, id => 'category',
            label       => 'call_category', type => 'select',
            value       => $_bind_call_category->( $categories, $incident ) },
         category_other => {
            disabled    => $disabled,
            label_class => $incident->id && $incident->category eq 'other'
                         ? NUL : 'hidden',
            label_id    => 'category_other_field' },
         notes          => {
            class       => 'standard-field autosize',
            disabled    => $disabled, type => 'textarea' },
         committee_informed => $incident->id ? {
            disabled    => $disabled, type => 'datetime',
            value       => $incident->committee_informed_label( $req )} : FALSE,
         committee_member_id => $incident->id ? {
            disabled    => $disabled,
            label       => 'committee_member', type => 'select',
            value       => $self->$_bind_committee_member( $incident )} : FALSE,
       ];
};

my $_find_person = sub {
   my ($self, $scode) = @_; my $rs = $self->schema->resultset( 'Person' );

   return $rs->find_by_shortcode( $scode );
};

my $_incident_ops_links = sub {
   my ($self, $req, $iid) = @_; my $links = [];

   my $actionp = $self->moniker.'/incident_party';
   my $href = uri_for_action $req, $actionp, [ $iid ];

   p_link $links, 'incident_party', $href, {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_incident_party_ops_links = sub {
   my ($self, $req, $page, $iid) = @_; my $links = [];

   my $actionp = $self->moniker.'/incident';

   p_link $links, 'incident', uri_for_action( $req, $actionp, [ $iid ] ), {
      action => 'view', container_class => 'table-link', request => $req };

   return $links;
};

my $_incidents_ops_links = sub {
   my ($self, $req, $page, $params, $pager) = @_; my $links = [];

   my $actionp = $self->moniker.'/incident';

   p_link $links, 'incident', uri_for_action( $req, $actionp ), {
      action => 'create', container_class => 'add-link', request => $req };

   $actionp = $self->moniker.'/incidents';

   my $page_links = page_link_set $req, $actionp, [], $params, $pager;

   $page_links and push @{ $links }, $page_links;

   return $links;
};

my $_incidents_row = sub {
   my ($self, $req, $incident) = @_;

   my $href = uri_for_action $req, $self->moniker.'/incident', [ $incident->id];

   return [ { value => f_link 'incident_record', $href, {
      request => $req, value => $incident->title, } },
            { value => $incident->raised_label( $req ) },
            { value => locm $req, $incident->category }, ];
};

my $_list_all_people = sub {
   my $self = shift; my $rs = $self->schema->resultset( 'Person' );

   return [ map { [ $_->label, $_->shortcode ] } $rs->search( {} )->all ];
};

my $_maybe_find = sub {
   my ($self, $class, $id) = @_; $id or return Class::Null->new;

   return $self->schema->resultset( $class )->find( $id );
};

my $_update_incident_from_request = sub {
   my ($self, $req, $incident) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE };

   for my $attr (qw( category_id title reporter reporter_phone category_other
                     notes committee_informed committee_member_id )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      if (length $v and is_member $attr, [ qw( committee_informed ) ]) {
         $v =~ s{ [@] }{}mx; $v = to_dt $v;
      }

      $attr eq 'committee_member_id' and (length $v or $v = undef);
      $incident->$attr( $v );
   }

   if ($incident->committee_informed or $incident->committee_member_id) {
      ($incident->committee_informed and $incident->committee_member_id)
         or throw 'Must set date and member if committee informed';
   }

   $incident->controller_id( $self->$_find_person( $req->username )->id );

   return;
};

# Public methods
sub add_incident_party_action : Role(controller) {
   my ($self, $req) = @_;

   my $iid = $req->uri_params->( 0 );
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $parties = $req->body_params->( 'people', { multiple => TRUE } );
   my $incident_party_rs = $self->schema->resultset( 'IncidentParty' );

   for my $scode (@{ $parties }) {
      my $person = $self->$_find_person( $scode );

      $incident_party_rs->create( {
         incident_party_id => $person->id, incident_id => $iid } );

      my $message = "action:add-incident_party incident_id:${iid} "
                  . "shortcode:${scode}";

      $self->send_event( $req, $message );
   }

   my $message = [ to_msg '[_1] incident incident_party added by [_2]',
                   $incident->title, $req->session->user_label ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub create_incident_action : Role(controller) {
   my ($self, $req) = @_;

   my $incident = $self->schema->resultset( 'Incident' )->new_result( {} );

   $self->$_update_incident_from_request( $req, $incident );

   my $title = $incident->title;

   try   { $incident->insert }
   catch { $self->blow_smoke( $_, 'create', 'incident', $title ) };

   my $iid = $incident->id; $title =~ s{ [ ] }{_}gmx; $title = lc $title;
   my $message = "action:create-incident incident_id:${iid} "
               . "incident_title:${title}";

   $self->send_event( $req, $message );

   my $who = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/incident', [ $iid ];

   $message = [ to_msg 'Incident [_1] created by [_2]', $iid, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_incident_action : Role(controller) {
   my ($self, $req) = @_;

   my $iid      = $req->uri_params->( 0 );
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $title    = $incident->title;

   $incident->delete; $title =~ s{ [ ] }{_}gmx; $title = lc $title;

   my $message  = "action:delete-incident incident_id:${iid} "
                . "incident_title:${title}";

   $self->send_event( $req, $message );

   my $who      = $req->session->user_label;
   my $location = uri_for_action $req, $self->moniker.'/incidents';

   $message = [ to_msg 'Incident [_1] deleted by [_2]', $iid, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub incident : Role(controller) {
   my ($self, $req) = @_;

   my $iid = $req->uri_params->( 0, { optional => TRUE } );
   my $href = uri_for_action $req, $self->moniker.'/incident', [ $iid ];
   my $action = $iid ? 'update' : 'create';
   my $form = blank_form 'incident', $href;
   my $page = {
      forms => [ $form ], selected => 'incidents',
      title => locm $req, 'incident_title',
   };
   my $links = $self->$_incident_ops_links( $req, $iid );
   my $incident = $self->$_maybe_find( 'Incident', $iid );
   my $fopts = { disabled => FALSE };

   $iid and p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_fields $form, $self->schema, 'Incident', $incident,
      $self->$_bind_incident_fields( $req, $page, $incident, $fopts );

   p_action $form, $action, [ 'incident', $iid ], { request => $req };

   $iid and p_action $form, 'delete', [ 'incident', $iid ], { request => $req };

   $_add_incident_js->( $page, $iid );

   return $self->get_stash( $req, $page );
}

sub incident_party : Role(controller) {
   my ($self, $req) = @_;

   my $iid  = $req->uri_params->( 0 );
   my $href = uri_for_action $req, $self->moniker.'/incident_party', [ $iid ];
   my $form = blank_form 'incident_party', $href;
   my $page = {
      forms => [ $form ], selected => 'incidents',
      title => locm $req, 'incident_party_title'
   };
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $title = $incident->title;
   my $parties = [ map { [ $_->person->label, $_->person->shortcode ] }
                   $incident->parties->all ];
   my $people = $_subtract->( $self->$_list_all_people, $parties );
   my $links = $self->$_incident_party_ops_links( $req, $page, $iid );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   p_textfield $form, 'incident', $title, {
      disabled => TRUE, label => 'incident_title' };
   p_textfield $form, 'raised', $incident->raised_label( $req ), {
      disabled => TRUE };

   p_select $form, 'incident_party', $parties, {
      label => 'incident_party_people', multiple => TRUE, size => 5 };

   my $tip = make_tip $req, 'remove_incident_party_tip', [ 'person', $title ];

   p_button $form, 'remove_incident_party', 'remove_incident_party', {
      class => 'delete-button', container_class => 'right-last', tip => $tip };

   p_container $form, f_tag( 'hr' ), { class => 'form-separator' };

   p_select $form, 'people', $people, { multiple => TRUE, size => 5 };

   p_button $form, 'add_incident_party', 'add_incident_party', {
      class => 'save-button', container_class => 'right-last',
      tip   => make_tip $req, 'add_incident_party_tip', [ 'person', $title ] };

   return $self->get_stash( $req, $page );
}

sub incidents : Role(controller) {
   my ($self, $req) = @_;

   my $params = $req->query_params->( {
      optional => TRUE } ); delete $params->{mid};
   my $form = blank_form;
   my $page = {
      forms => [ $form ], selected => 'incidents',
      title => locm $req, 'incidents_title',
   };
   my $opts      =  {
      controller => $req->username,
      is_manager => is_member( 'incident_manager', $req->session->roles ),
      page       => delete $params->{page} // 1,
      rows       => $req->session->rows_per_page,
   };
   my $rs = $self->schema->resultset( 'Incident' );
   my $incidents = $rs->search_for_incidents( $opts );
   my $links = $self->$_incidents_ops_links
      ( $req, $page, $params, $incidents->pager );

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   my $table = p_table $form, { headers => $_incidents_headers->( $req ) };

   p_row $table, [ map { $self->$_incidents_row( $req, $_ ) }
                   $incidents->all ];

   return $self->get_stash( $req, $page );
}

sub remove_incident_party_action : Role(controller) {
   my ($self, $req) = @_;

   my $iid = $req->uri_params->( 0 );
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $parties = $req->body_params->( 'incident_party', { multiple => TRUE } );
   my $incident_party_rs = $self->schema->resultset( 'IncidentParty' );

   for my $scode (@{ $parties }) {
      my $person = $self->$_find_person( $scode );

      $incident_party_rs->find( $iid, $person->id )->delete;

      my $message = "action:remove-incident_party incident_id:${iid} "
                  . "shortcode:${scode}";

      $self->send_event( $req, $message );
   }

   my $who = $req->session->user_label;
   my $message = [ to_msg '[_1] incident incident_party removed by [_2]',
                   $incident->title, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub update_incident_action : Role(controller) {
   my ($self, $req) = @_;

   my $iid = $req->uri_params->( 0 );
   my $incident = $self->schema->resultset( 'Incident' )->find( $iid );
   my $title = $incident->title;

   $self->$_update_incident_from_request( $req, $incident );

   try   { $incident->update }
   catch { $self->blow_smoke( $_, 'update', 'incident', $iid ) };

   $title =~ s{ [ ] }{_}gmx; $title = lc $title;

   my $message = "action:update-incident incident_id:${iid} "
               . "incident_title:${title}";

   $self->send_event( $req, $message );

   my $who = $req->session->user_label;

   $message = [ to_msg 'Incident [_1] updated by [_2]', $iid, $who ];

   return { redirect => { location => $req->uri, message => $message } };
}


1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Incident - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Incident;
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

Copyright (c) 2017 Peter Flanigan. All rights reserved

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
