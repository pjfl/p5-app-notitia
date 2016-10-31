package App::Notitia::Plugin::Email;

use namespace::autoclean;

use App::Notitia::Constants qw( FALSE NUL TRUE );
use App::Notitia::Util      qw( event_handler local_dt locm uri_for_action );
use Moo;

with q(Web::Components::Role);

# Public attributes
has '+moniker' => default => 'email';

# Private methods
my $_template_dir = sub {
   my ($self, $req) = @_; my $conf = $self->config; my $root = $conf->docs_root;

   return $root->catdir( $req->locale, $conf->posts, $conf->email_templates );
};

my $_event_email = sub {
   my ($self, $req, $stash) = @_; my $file = 'event_email.md';

   my $rs = $self->schema->resultset( 'Event' );
   my $event = $rs->find_event_by( $stash->{event_uri} );

   for my $k ( qw( description end_time name start_time ) ) {
      $stash->{ $k } = $event->$k();
   }

   $stash->{owner} = $event->owner->label;
   $stash->{date} = local_dt( $event->start_date )->dmy( '/' );
   $stash->{uri} = uri_for_action $req, 'event/event_summary', [ $event->uri ];
   $stash->{role} = 'fund_raiser';
   $stash->{template} = $self->$_template_dir( $req )->catfile( $file );

   return $stash;
};

# Event handlers
event_handler 'email', create_certification => sub {
   my ($self, $req, $stash) = @_; my $file = 'certification_email.md';

   $stash->{template} = $self->$_template_dir( $req )->catfile( $file );
   $stash->{type} = locm $req, $stash->{type};

   return $stash;
};

event_handler 'email', create_event => \&{ $_event_email };
event_handler 'email', update_event => \&{ $_event_email };

event_handler 'email', impending_slot => sub {
   my ($self, $req, $stash) = @_; my $file = 'impending_slot_email.md';

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $stash->{slot_key};

   $stash->{shift_type} = $shift_type;
   $stash->{slot_type} = $slot_type;
   $stash->{template} = $self->$_template_dir( $req )->catfile( $file );

   return $stash;
};

event_handler 'email', vacant_slot => sub {
   my ($self, $req, $stash) = @_;

   my $slot_type = $stash->{role} = $stash->{slot_type};
   my $file = "${slot_type}_slots_email.md";

   $stash->{template} = $self->$_template_dir( $req )->catfile( $file );

   return $stash;
};

event_handler 'email', vehicle_assignment => sub {
   my ($self, $req, $stash) = @_; my $file;

   if ($stash->{slot_key}) {
      my ($shift_type, $slot_type, $subslot)
         = split m{ _ }mx, $stash->{slot_key};

      $stash->{shift_type} = $shift_type;
      $stash->{slot_type} = $slot_type;
      $file = 'vehicle_assignment_email.md';
   }
   elsif ($stash->{event_uri}) {
      $file = 'vehicle_assignment_event_email.md';
   }

   $file and $stash->{template}
      = $self->$_template_dir( $req )->catfile( $file );

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