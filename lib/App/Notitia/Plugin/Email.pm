package App::Notitia::Plugin::Email;

use namespace::autoclean;

use App::Notitia::Constants qw( FALSE NUL TRUE );
use App::Notitia::Util      qw( event_handler locd locm uri_for_action );
use Class::Usul::Functions  qw( throw );
use Moo;

with q(Web::Components::Role);

# Public attributes
has '+moniker' => default => 'email';

# Private methods
my $_event_email = sub {
   my ($self, $req, $stash) = @_;

   my $rs = $self->schema->resultset( 'Event' );
   my $event = $rs->find_event_by( $stash->{event_uri} );

   for my $k ( qw( description end_time name start_time ) ) {
      $stash->{ $k } = $event->$k();
   }

   $stash->{template} = 'event_email.md';
   $stash->{owner} = $event->owner->label;
   $stash->{date} = locd $req, $event->start_date;
   $stash->{uri} = uri_for_action $req, 'event/event_summary', [ $event->uri ];

   return $stash;
};

# Event handlers
event_handler 'email', add_course => sub {
   my ($self, $req, $stash) = @_;

   $stash->{course} = locm $req, $stash->{course};
   $stash->{uri} = uri_for_action $req, 'train/events';

   return $stash;
};

event_handler 'email', application_upgraded => sub {
   my ($self, $req, $stash) = @_;

   $stash->{time} =~ s{ \. }{:}mx;

   return $stash;
};

event_handler 'email', create_certification => sub {
   my ($self, $req, $stash) = @_;

   $stash->{type} = locm $req, $stash->{type};

   return $stash;
};

event_handler 'email', create_delivery_stage => sub {
   my ($self, $req, $stash) = @_;

   my $id = $stash->{stage_id} or throw 'No stage_id in create_delivery_stage';
   my $opts = { prefetch => { 'journey' => 'packages' } };
   my $leg = $self->schema->resultset( 'Leg' )->find( { id => $id }, $opts )
      or throw "Stage id ${id} unknown";
   my $journey = $leg->journey;

   $stash->{template} = 'delivery_stage_email.md';
   $stash->{controller} = $journey->controller->label;
   $stash->{beginning} = $leg->beginning.NUL;
   $stash->{ending} = $leg->ending.NUL;
   $stash->{called} = $leg->called_label( $req );
   $stash->{collection_eta} = $leg->collection_eta_label( $req );
   $stash->{priority} = $journey->priority.NUL;
   $stash->{packages} = [ map {
      [ $_->quantity, $_->package_type.NUL, $_->description ] }
                          $journey->packages->all ];

   return $stash;
};

event_handler 'email', create_event => \&{ $_event_email };
event_handler 'email', update_event => \&{ $_event_email };

event_handler 'email', impending_slot => sub {
   my ($self, $req, $stash) = @_;

   my ($shift_type, $slot_type, undef) = split m{ _ }mx, $stash->{slot_key};

   $stash->{shift_type} = $shift_type;
   $stash->{slot_type} = $slot_type;

   return $stash;
};

event_handler 'email', vacant_slot => sub {
   my ($self, $req, $stash) = @_;

   my $args = [ $stash->{rota_name}, $stash->{rota_date} ];

   $stash->{role} = $stash->{slot_type};
   $stash->{uri} = uri_for_action $req, 'day/day_rota', $args;

   return $stash;
};

event_handler 'email', vehicle_assignment => sub {
   my ($self, $req, $stash) = @_;

   if ($stash->{slot_key}) {
      my $rs = $self->schema->resultset( 'Vehicle' );
      my ($shift_type, $slot_type, undef) = split m{ _ }mx, $stash->{slot_key};

      $stash->{shift_type} = $shift_type;
      $stash->{slot_type} = $slot_type;
      $stash->{subject} = locm $req, 'Vehicle Assignment [_1]', $stash->{date};
      $stash->{vehicle} = $rs->find_vehicle_by( $stash->{vehicle} )->label;
   }
   elsif ($stash->{event_uri}) {
      $stash->{template} = 'vehicle_assignment_event_email.md';
   }
   else { return TRUE }

   return $stash;
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Plugin::Email - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Plugin::Email;
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
