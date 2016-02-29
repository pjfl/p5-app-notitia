package App::Notitia::Model::Event;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind delete_button
                                loc register_action_paths
                                save_button uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( throw );
use Class::Usul::Time       qw( str2date_time );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'event';

register_action_paths
   'event/event'  => 'event',
   'event/events' => 'events';

# Private functions
my $_bind_event_fields = sub {
   my $event = shift;

   return {
      description => bind( 'description', $event->description,
                           { class     => 'autosize' } ),
      end         => bind( 'end',         $event->end ),
      event_name  => bind( 'event_name',  $event->name ),
      owner       => bind( 'owner',       $event->owner ),
      notes       => bind( 'notes',       $event->notes,
                           { class     => 'autosize' } ),
      start       => bind( 'start',       $event->start ),
   };
};

# Private methods
my $_find_event_by = sub {
   my ($self, $name) = @_;

   my $event_rs = $self->schema->resultset( 'Event' );
   my $event    = $event_rs->search( { name => $name } )->single
      or throw 'Event [_1] unknown', [ $name ], rv => HTTP_EXPECTATION_FAILED;

   return $event;
};

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav} = admin_navigation_links $req;

   return $stash;
};

# Public methods
sub event {
   my ($self, $req) = @_;

   my $name    =  $req->uri_params->( 0, { optional => TRUE } );
   my $event   =  $name ? $self->$_find_event_by( $name ) : Class::Null->new;
   my $page    =  {
      fields   => $_bind_event_fields->( $event ),
      template => [ 'contents', 'event' ],
      title    => loc( $req, 'event_management_heading' ), };
   my $fields  =  $page->{fields};

   $name and $fields->{date      } = bind( 'date', $event->rota->date );
   $name and $fields->{delete    } = delete_button( $req, $name, 'event' );
   $name and $fields->{event_href} = uri_for_action( 'event/event', [ $name ] );
             $fields->{save      } = save_button( $req, $name, 'event' );

   return $self->get_stash( $req, $page );
}

sub events {
   my ($self, $req) = @_;

   my $page = { template => [ 'contents', 'table' ] };

   return $self->get_stash( $req, $page );
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
