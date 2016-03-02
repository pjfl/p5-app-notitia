package App::Notitia::Model::Event;

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
has '+moniker' => default => 'event';

register_action_paths
   'event/event'       => 'event',
   'event/events'      => 'events',
   'event/participent' => 'participate';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Private class attributes
my $_admin_links_cache = {};

# Private functions
my $_bind_event_fields = sub {
   my $event = shift;

   return {
      description => bind( 'description', $event->description,
                           { class     => 'autosize' } ),
      end_time    => bind( 'end_time',    $event->end_time ),
      name        => bind( 'event_name',  $event->name ),
      notes       => bind( 'notes',       $event->notes,
                           { class     => 'autosize' } ),
      start_time  => bind( 'start_time',  $event->start_time ),
   };
};

my $_events_headers = sub {
   return [ map { { value => loc( $_[ 0 ], "events_heading_${_}" ) } } 0 .. 2 ];
};

my $_select_owner_list = sub {
   return bind( 'owner', [ [ NUL, NUL ], @{ $_[ 0 ] } ], { numify => TRUE } );
};

# Private methods
my $_event_admin_links = sub {
   my ($self, $req, $name) = @_; my $links = $_admin_links_cache->{ $name };

   $links and return @{ $links }; $links = [];

   for my $action ( qw( event participent ) ) {
      my $href = uri_for_action( $req, $self->moniker."/${action}", [ $name ] );

      push @{ $links }, {
         value => { class => 'table-link fade',
                    hint  => loc( $req, 'Hint' ),
                    href  => $href,
                    name  => "${name}-${action}",
                    tip   => loc( $req, "${action}_management_tip" ),
                    type  => 'link',
                    value => loc( $req, "${action}_management_link" ), }, };
   }

   $_admin_links_cache->{ $name } = $links;

   return @{ $links };
};

my $_find_rota = sub {
   return $_[ 0 ]->schema->resultset( 'Rota' )->find_rota( $_[ 1 ], $_[ 2 ] );
};

my $_update_event_from_request = sub {
   my ($self, $req, $event) = @_; my $params = $req->body_params;

   my $opts = { optional => TRUE, scrubber => '[^ +\,\-\./0-9@A-Z\\_a-z~]' };

   $event->name( $params->( 'event_name' ) );

   for my $attr (qw( description end_time notes start_time )) {
      my $v = $params->( $attr, $opts ); defined $v or next;

      is_member $attr, [ 'end_time', 'start_time' ]
          and $v =~ s{ \A (\d\d) (\d\d) \z }{$1:$2}mx;

      $event->$attr( $v );
   }

   my $v = $params->( 'owner', $opts ); defined $v and $event->owner_id( $v );

   return;
};

# Public methods
sub create_event_action : Role(administrator) Role(event_manager) {
   my ($self, $req) = @_;

   my $date     =  $req->body_params->( 'event_date' );
   my $event    =  $self->schema->resultset( 'Event' )->new_result
      ( { rota  => 'main', # TODO: Naughty
          date  => str2date_time( $date, 'GMT' ),
          owner => $req->username, } );

   $self->$_update_event_from_request( $req, $event ); $event->insert;

   my $action   =  $self->moniker.'/event';
   my $location =  uri_for_action( $req, $action, [ $event->name ] );
   my $message  =
      [ 'Event [_1] created by [_2]', $event->name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_event_action : Role(administrator) Role(event_manager) {
   my ($self, $req) = @_;

   my $name  = $req->uri_params->( 0 );
   my $event = $self->schema->resultset( 'Event' )->find_event_by( $name );

   $event->delete;

   my $location = uri_for_action( $req, $self->moniker.'/events' );
   my $message  = [ 'Event [_1] deleted by [_2]', $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub event : Role(administrator) Role(event_manager) {
   my ($self, $req) = @_;

   my $event_rs =  $self->schema->resultset( 'Event' );
   my $name     =  $req->uri_params->( 0, { optional => TRUE } );
   my $opts     =  { prefetch => [ 'owner' ] };
   my $event    =  $name ? $event_rs->find_event_by( $name, $opts )
                         : Class::Null->new;
   my $page     =  {
      fields    => $_bind_event_fields->( $event ),
      template  => [ 'contents', 'event' ],
      title     => loc( $req, 'event_management_heading' ), };
   my $fields   =  $page->{fields};
   my $action   =  $self->moniker.'/event';

   if ($name) {
      my $person_rs = $self->schema->resultset( 'Person' );

      $fields->{date  } = bind( 'event_date', $event->rota->date );
      $fields->{delete} = delete_button( $req, $name, 'event' );
      $fields->{href  } = uri_for_action( $req, $action, [ $name ] );
      $fields->{owner } = $_select_owner_list->( $person_rs->list_all_people
         ( { selected => $event->owner } ) );
   }
   else {
      $fields->{date} = bind( 'event_date', time2str '%Y-%m-%d' );
   }

   $fields->{save} = save_button( $req, $name, 'event' );

   return $self->get_stash( $req, $page );
}

sub events : Role(any) {
   my ($self, $req) = @_;

   my $page     =  {
      fields    => { headers => $_events_headers->( $req ), rows => [], },
      template  => [ 'contents', 'table' ],
      title     => loc( $req, 'events_management_heading' ), };
   my $rows     =  $page->{fields}->{rows};
   my $event_rs =  $self->schema->resultset( 'Event' );

   for my $event (@{ $event_rs->list_all_events() }) {
      push @{ $rows },
         [ { value => $event->[ 0 ] },
           $self->$_event_admin_links( $req, $event->[ 1 ]->name ) ];
   }

   return $self->get_stash( $req, $page );
}

sub update_event_action : Role(administrator) Role(event_manager) {
   my ($self, $req) = @_;

   my $name  = $req->uri_params->( 0 );
   my $event = $self->schema->resultset( 'Event' )->find_event_by( $name );
   my $date  = str2date_time $req->body_params->( 'event_date' ) , 'GMT';

   $self->$_update_event_from_request( $req, $event );
   $event->rota_id( $self->$_find_rota( 'main', $date )->id ); # TODO: Naughty
   $event->update;

   my $message = [ 'Event [_1] updated by [_2]', $name, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Event - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Event;
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
