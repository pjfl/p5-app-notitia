package App::Notitia::Plugin::Core;

use namespace::autoclean;

use App::Notitia::Util qw( event_handler locm );
use Moo;

with q(Web::Components::Role);

# Public attributes
has '+moniker' => default => 'core';

# Event callbacks
# Condition
event_handler 'condition', '_sink_' => sub {
   my ($self, $req, $stash) = @_; return $stash->{message_sink1};
};

event_handler 'condition', '_sink_' => sub {
   my ($self, $req, $stash) = @_; return $stash->{message_sink2};
};

# Email
event_handler 'email', '_buildargs_' => sub {
   my ($self, $req, $stash) = @_;

   $stash->{status} = 'current';
   $stash->{subject} = locm $req, $stash->{action}.'_email_subject';

   return $stash;
};

event_handler 'email', '_sink_' => sub {
   my ($self, $req, $stash) = @_;

   my $template = delete $stash->{template} or return;

   if ($template->exists) { $self->create_email_job( $stash, $template ) }
   else { $self->log->warn( "Email template ${template} does not exist" ) }

   return;
};

# SMS
event_handler 'sms', '_sink_' => sub {
   my ($self, $req, $stash) = @_;

   my $message = delete $stash->{message}; $message
      and $self->create_sms_job( $stash, $message ) and return;

   return;
};

# Update
event_handler 'update', '_sink_' => sub {
   my ($self, $req, $stash) = @_;

   my $actionp = delete $stash->{action_path}; $actionp
      and return $self->event_component_update( $req, $stash, $actionp );

   return;
};

event_handler 'update', '_sink_' => sub {
   my ($self, $req, $stash) = @_;

   my $resultp = delete $stash->{result_path}; $resultp
      and return $self->event_schema_update( $req, $stash, $resultp );

   return;
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
