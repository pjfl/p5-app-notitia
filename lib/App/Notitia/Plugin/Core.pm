package App::Notitia::Plugin::Core;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE TRUE );
use App::Notitia::Util      qw( event_handler local_dt locm uri_for_action );
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Types      qw( ArrayRef NonEmptySimpleStr );
use Unexpected::Functions   qw( Unspecified );
use Moo;

with q(Web::Components::Role);

# Public attributes
has '+moniker' => default => 'core';

has 'certifiable_courses' => is => 'ro', isa => ArrayRef[NonEmptySimpleStr],
   builder                => sub { [] };

# Private methods
my $_template_dir = sub {
   my ($self, $req) = @_; my $conf = $self->config; my $root = $conf->docs_root;

   return $root->catdir( $req->locale, $conf->posts, $conf->email_templates );
};

# Event callbacks
# Condition
event_handler 'sink', condition => sub {
   exists $_[ 2 ]->{condition_branch1}
      and $_[ 0 ]->send_event( $_[ 1 ], $_[ 2 ]->{condition_branch1} );
   return;
};

event_handler 'sink', condition => sub {
   exists $_[ 2 ]->{condition_branch2}
      and $_[ 0 ]->send_event( $_[ 1 ], $_[ 2 ]->{condition_branch2} );
   return;
};

# Email
event_handler 'buildargs', email => sub {
   my ($self, $req, $stash) = @_;

   $stash->{status} = 'current';
   $stash->{subject} = locm $req, $stash->{action}.'_email_subject';

   return $stash;
};

event_handler 'sink', email => sub {
   my ($self, $req, $stash) = @_;

   my $template = delete $stash->{template} or return;

   $template->exists and return $self->create_email_job( $stash, $template );

   $self->log->warn( "Email template ${template} does not exist" );

   return;
};

event_handler 'email', create_certification => sub {
   my ($self, $req, $stash) = @_; my $file = 'certification_email.md';

   $stash->{template} = $self->$_template_dir( $req )->catfile( $file );
   $stash->{type} = locm $req, $stash->{type};

   return $stash;
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

# Update
event_handler 'sink', update => sub {
   my ($self, $req, $stash) = @_;

   my $actionp = delete $stash->{action_path} or return;
   my ($moniker, $method) = split m{ / }mx, $actionp;
   my $compo = $self->components->{ $moniker }
      or throw 'Model moniker [_1] unknown', [ $moniker ];

   $method or throw Unspecified, [ 'update method' ];
   $compo->can( $method )
      or throw 'Model [_1] has no method [_2]', [ $moniker, $method ];
   $compo->$method( $req, $stash );
   return;
};

event_handler 'update', update_course => sub {
   my ($self, $req, $stash) = @_; delete $stash->{action_path};

   $stash->{status} eq 'completed' or return $stash;

   is_member $stash->{course}, $self->plugins->{core}->certifiable_courses
      and return {
         action_path => 'certs/create_certification_action',
         recipient   => $stash->{shortcode},
         type        => $stash->{course},
         completed   => $stash->{date},
         notes       => 'Automatically awarded by '.$self->config->title,
      };

   return $stash;
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Plugin::Core - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Plugin::Core;
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
