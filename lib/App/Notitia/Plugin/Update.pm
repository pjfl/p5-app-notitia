package App::Notitia::Plugin::Update;

use namespace::autoclean;

use App::Notitia::Constants qw( FALSE NUL TRUE );
use App::Notitia::Util      qw( event_handler );
use Class::Usul::Functions  qw( is_member );
use Class::Usul::Types      qw( ArrayRef NonEmptySimpleStr );
use Moo;

with q(Web::Components::Role);

# Public attributes
has '+moniker' => default => 'update';

has 'certifiable_courses' => is => 'ro', isa => ArrayRef[NonEmptySimpleStr],
   builder => sub { [] };

# Private methods
my $_maybe_delete_cert = sub {
   my ($self, $stash) = @_;

   is_member $stash->{course}, $self->plugins->{update}->certifiable_courses
      and return {
         action_path => 'certs/delete_certification_action',
         recipient   => $stash->{shortcode},
         type        => $stash->{course},
      };

   return;
};

# Event handlers
event_handler 'update', remove_course => sub {
   my ($self, $req, $stash) = @_; return $self->$_maybe_delete_cert( $stash );
};

event_handler 'update', update_course => sub {
   my ($self, $req, $stash) = @_;

   $stash->{status} eq 'completed' and
      is_member $stash->{course}, $self->plugins->{update}->certifiable_courses
      and return {
         action_path => 'certs/create_certification_action',
         recipient   => $stash->{shortcode},
         type        => $stash->{course},
         completed   => $stash->{date},
         notes       => 'Automatically awarded by '.$self->config->title,
      };

   return;
};

event_handler 'update', update_course => sub {
   my ($self, $req, $stash) = @_;

   $stash->{status} eq 'expired'
      and return $self->$_maybe_delete_cert( $stash );

   return;
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Plugin::Update - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Plugin::Update;
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
