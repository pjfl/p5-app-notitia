package App::Notitia::Role::EventStream;

use namespace::autoclean;

use App::Notitia::Constants qw( FALSE NUL SPC TRUE );
use App::Notitia::Util      qw( locm uri_for_action );
use Class::Usul::Log        qw( get_logger );
use Moo::Role;

requires qw( config create_email_job schema );

# Private functions
my $_local_dt = sub {
   return  $_[ 0 ]->clone->set_time_zone( 'local' );
};

# Private methods
my $_inflate = sub {
   my ($self, $req, $message) = @_;

   my $stash = { app_name => $self->config->title };

   for my $pair (split SPC, $message) {
      my ($k, $v) = split m{ : }mx, $pair; $stash->{ $k } = $v;
   }

   $stash->{action} =~ s{ [\-] }{_}gmx;
   $stash->{subject} = locm $req, $stash->{action}.'_email_subject';

   return $stash;
};

my $_template_dir = sub {
   my ($self, $req) = @_; my $conf = $self->config; my $root = $conf->docs_root;

   return $root->catdir( $req->locale, $conf->posts, $conf->email_templates );
};

my $_certification_email = sub {
   my ($self, $req, $stash) = @_;

   my $template =
      $self->$_template_dir( $req )->catfile( 'certification_email.md' );

   $stash->{type} = locm $req, $stash->{type};

   return $self->create_email_job( $stash, $template );
};

my $_event_email = sub {
   my ($self, $req, $stash) = @_;

   my $rs = $self->schema->resultset( 'Event' );
   my $event = $rs->find_event_by( $stash->{event} );
   my $template = $self->$_template_dir( $req )->catfile( 'event_email.md' );

   for my $k ( qw( description end_time name start_time ) ) {
      $stash->{ $k } = $event->$k();
   }

   $stash->{owner} = $event->owner->label;
   $stash->{start_date} = $_local_dt->( $event->start_date )->dmy( '/' );
   $stash->{uri} = uri_for_action $req, 'event/event_summary', [ $event->uri ];

   $stash->{role} = 'fund_raiser'; $stash->{status} = 'current';

   return $self->create_email_job( $stash, $template );
};

my $_slots_email = sub {
   my ($self, $req, $stash) = @_;

   my ($role) = $stash->{action} =~ m{ vacant_ ([^_]+) _slots }mx;
   my $file = "${role}_slots_email.md";
   my $template = $self->$_template_dir( $req )->catfile( $file );

   $stash->{role} = $role; $stash->{status} = 'current';

   return $self->create_email_job( $stash, $template );
};

# Public methods
sub send_event {
   my ($self, $req, $message) = @_; get_logger( 'activity' )->log( $message );

   my $stash = $self->$_inflate( $req, $message );

   $stash->{action} eq 'create_certification'
      and $self->$_certification_email( $req, $stash );

   ($stash->{action} eq 'create_event' or $stash->{action} eq 'update_event')
      and $self->$_event_email( $req, $stash );

   $stash->{action} =~ m{ vacant_ (?: controller|driver|rider ) _slots }mx
      and $self->$_slots_email( $req, $stash );

   return;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::EventStream - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::EventStream;
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
