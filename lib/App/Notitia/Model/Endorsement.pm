package App::Notitia::Model::Endorsement;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL PIPE_SEP SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_action p_list p_fields
                                p_row p_table p_textfield );
use App::Notitia::Util      qw( check_field_js loc locm register_action_paths
                                to_dt to_msg uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Time       qw( time2str );
use Try::Tiny;
use Unexpected::Functions   qw( ValidationErrors );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

# Public attributes
has '+moniker' => default => 'blots';

register_action_paths
   'blots/endorsement'  => 'endorsement',
   'blots/endorsements' => 'endorsements';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} = 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_endorsements_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "blots_heading_${_}" ) } } 0 .. 1 ];
};

my $_endorsement_ops_links = sub {
   my ($req, $actionp, $person) = @_;

   my $href = uri_for_action $req, $actionp, [ $person->shortcode ];
   my $opts = { action => 'add', args => [ $person->label ], request => $req };

   return [ f_link 'endorsement', $href, $opts ];
};

my $_link_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

# Private methods
my $_endorsement_js = sub {
   my $self = shift;
   my $opts = { domain => 'schedule', form => 'Endorsement' };

   return [ check_field_js( 'type_code', $opts ),
            check_field_js( 'endorsed',  $opts ), ];
};

my $_bind_endorsement_fields = sub {
   my ($self, $blot, $opts) = @_; $opts //= {};

   my $today    = to_dt time2str '%Y-%m-%d';
   my $updating = $opts->{action} eq 'update' ? TRUE : FALSE;
   my $endorsed = $updating ? $blot->endorsed : $today;

   return
   [  type_code => { class => 'standard-field server', disabled => $updating },
      endorsed  => { class => 'standard-field server', type => 'date',
                     value => $endorsed },
      points    => {},
      notes     => { class => 'standard-field autosize', type => 'textarea' },
      ];
};

my $_endorsement_links = sub {
   my ($self, $req, $scode, $blot) = @_;

   my $args = [ $blot->recipient->label ]; my @links;

   for my $actionp (map { $self->moniker."/${_}" } 'endorsement' ) {
      my $href = uri_for_action $req, $actionp, [ $scode, $blot->uri ];
      my $opts = { action => 'update', args => $args, request => $req };

      push @links, { value => f_link 'endorsement', $href, $opts };
   }

   return [ { value => $blot->label( $req ) }, @links ];
};

my $_find_endorsement_by = sub {
   my ($self, @args) = @_; my $schema = $self->schema;

   return $schema->resultset( 'Endorsement' )->find_endorsement_by( @args );
};

my $_maybe_find_endorsement = sub {
   return $_[ 2 ] ? $_[ 0 ]->$_find_endorsement_by( $_[ 1 ], $_[ 2 ] )
                  : Class::Null->new;
};

my $_update_endorsement_from_request = sub {
   my ($self, $req, $blot) = @_;

   my $params = $req->body_params; my $opts = { optional => TRUE };

   for my $attr (qw( type_code endorsed notes points )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts );

      defined $v or next; $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      length $v and is_member $attr, [ qw( endorsed ) ] and $v = to_dt $v;

      $blot->$attr( $v );
   }

   return;
};

# Public methods
sub create_endorsement_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0 );
   my $blot_rs = $self->schema->resultset( 'Endorsement' );
   my $blot    = $blot_rs->new_result( { recipient => $name } );

   $self->$_update_endorsement_from_request( $req, $blot );

   try   { $blot->insert }
   catch {
      $self->rethrow_exception
         ( $_, 'create', 'endorsement', $blot->label( $req ) );
   };

   my $type     = $blot->type_code;
   my $who      = $req->session->user_label;
   my $action   = $self->moniker.'/endorsements';
   my $location = uri_for_action $req, $action, [ $name ];
   my $key      = 'Endorsement [_1] for [_2] added by [_3]';
   my $message  = 'user:'.$req->username.' client:'.$req->address.SPC
                . "action:create-endorsement shortcode:${name} type:${type}";

   $self->send_event( $req, $message );
   $message = [ to_msg $key, $type, $name, $who ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_endorsement_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $uri      = $req->uri_params->( 1 );
   my $blot     = $self->$_find_endorsement_by( $name, $uri ); $blot->delete;
   my $action   = $self->moniker.'/endorsements';
   my $location = uri_for_action $req, $action, [ $name ];
   my $key      = 'Endorsement [_1] for [_2] deleted by [_3]';
   my $message  = 'user:'.$req->username.' client:'.$req->address.SPC
                . "action:delete-endorsement shortcode:${name} blot:${uri}";

   $self->send_event( $req, $message );
   $message = [ to_msg $key, $uri, $name, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub endorsement : Role(person_manager) {
   my ($self, $req) = @_;

   my $actionp    =  $self->moniker.'/endorsement';
   my $name       =  $req->uri_params->( 0 );
   my $uri        =  $req->uri_params->( 1, { optional => TRUE } );
   my $action     =  $uri ? 'update' : 'create';
   my $href       =  uri_for_action $req, $actionp, [ $name, $uri ];
   my $form       =  blank_form 'endorsement-admin', $href;
   my $page       =  {
      first_field => $uri ? 'endorsed' : 'type_code',
      forms       => [ $form ],
      literal_js  => $self->$_endorsement_js(),
      title       => loc $req, "endorsement_${action}_heading" };
   my $blot       =  $self->$_maybe_find_endorsement( $name, $uri );
   my $person_rs  =  $self->schema->resultset( 'Person' );
   my $person     =  $person_rs->find_by_shortcode( $name );
   my $args       =  [ 'endorsement', $person->label ];

   p_textfield $form, 'username', $person->label, { disabled => TRUE };

   p_fields $form, $self->schema, 'Endorsement', $blot,
      $self->$_bind_endorsement_fields( $blot, { action => $action } );

   p_action $form, $action, $args, { request => $req };

   $uri and p_action $form, 'delete', $args, { request => $req };

   return $self->get_stash( $req, $page );
}

sub endorsements : Role(person_manager) {
   my ($self, $req) = @_;

   my $actionp =  $self->moniker.'/endorsement';
   my $scode   =  $req->uri_params->( 0 );
   my $form    =  blank_form;
   my $page    =  {
      forms    => [ $form ],
      title    => loc $req, 'endorsements_management_heading' };
   my $schema  =  $self->schema;
   my $person  =  $schema->resultset( 'Person' )->find_by_shortcode( $scode );
   my $blot_rs =  $schema->resultset( 'Endorsement' );
   my $links   =  $_endorsement_ops_links->( $req, $actionp, $person );

   p_textfield $form, 'username', $person->label, { disabled => TRUE };

   my $table = p_table $form, { headers => $_endorsements_headers->( $req ) };

   p_row $table, [ map { $self->$_endorsement_links( $req, $scode, $_ ) }
                   $blot_rs->search_for_endorsements( $scode )->all ];

   p_list $form, PIPE_SEP, $links, $_link_opts->();

   return $self->get_stash( $req, $page );
}

sub update_endorsement_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0 );
   my $uri  = $req->uri_params->( 1 );
   my $blot = $self->$_find_endorsement_by( $name, $uri );

   $self->$_update_endorsement_from_request( $req, $blot ); $blot->update;

   my $key     = 'Endorsement [_1] for [_2] updated by [_3]';
   my $message = 'user:'.$req->username.' client:'.$req->address.SPC
               . "action:update-endorsement shortcode:${name} blot:${uri}";

   $self->send_event( $req, $message );
   $message = [ to_msg $key, $uri, $name, $req->session->user_label ];

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
