package App::Notitia::Plugin::Core;

use namespace::autoclean;

use App::Notitia::Constants qw( NUL );
use App::Notitia::Util      qw( event_handler locm );
use Scalar::Util            qw( blessed );
use Moo;

with q(Web::Components::Role);

# Public attributes
has '+moniker' => default => 'core';

# Private functions
my $_event_control_role = sub {
   my ($stash, $sink) = @_;

   my $tuple = $stash->{_event_control}->{ $sink }->{ $stash->{action} };

   return $tuple && $tuple->[ 1 ] ? $tuple->[ 1 ].NUL : 'individual';
};

# Private methods
my $_template_dir = sub {
   my ($self, $req) = @_; my $conf = $self->config; my $root = $conf->docs_root;

   return $root->catdir( $req->locale, $conf->posts, $conf->email_templates );
};

# Event callbacks. Zero or one _input_ handler. One or more _output_ handlers
# Condition
event_handler 'condition', '_output_' => sub {
   my ($self, $req, $stash) = @_; return $stash->{condition_output1};
};

event_handler 'condition', '_output_' => sub {
   my ($self, $req, $stash) = @_; return $stash->{condition_output2};
};

# Email
event_handler 'email', '_input_' => sub {
   my ($self, $req, $stash) = @_;

   $stash->{app_name} //= $self->config->title;
   $stash->{role    } //= $_event_control_role->( $stash, 'email' );
   $stash->{status  } //= 'current';
   $stash->{subject } //= locm $req, $stash->{action}.'_email_subject';
   $stash->{template} //= $stash->{action}.'_email.md';

   return $stash;
};

event_handler 'email', '_default_' => sub {
   my ($self, $req, $stash) = @_; return $stash;
};

event_handler 'email', '_output_' => sub {
   my ($self, $req, $stash) = @_; my $action = $stash->{action};

   not $stash->{role}
      and $self->log->warn( "No role in ${action} message" )
      and return;

   if ($stash->{role} eq 'individual') {
      not $stash->{shortcode}
          and $self->log->warn( "No shortcode in ${action} message" )
          and return;
      delete $stash->{role};
   }

   my $template = delete $stash->{template}; blessed $template
      or $template = $self->$_template_dir( $req )->catfile( $template );

   if ($template->exists) { $self->create_email_job( $stash, $template ) }
   else { $self->log->warn( "Email template ${template} does not exist" ) }

   return;
};

# Geolocation
my $_find_location = sub {
   return $_[ 0 ]->schema->resultset( 'Location' )->find( $_[ 1 ] );
};

my $_location_lookup = sub {
   my ($self, $req, $stash) = @_;

   my $id = delete $stash->{location_id}; $id
      and $stash->{target} = $self->$_find_location( $id )
      and return $stash;

   return;
};

event_handler 'geolocation', create_location => \&{ $_location_lookup };
event_handler 'geolocation', update_location => \&{ $_location_lookup };

event_handler 'geolocation', '_output_' => sub {
   my ($self, $req, $stash) = @_;;

   my $target = delete $stash->{target}; $target
      and $self->create_coordinate_lookup_job( $stash, $target );

   return;
};

# SMS
event_handler 'sms', '_input_' => sub {
   my ($self, $req, $stash) = @_;

   $stash->{message} //= $stash->{action}.'_sms.md';
   $stash->{role   } //= $_event_control_role->( $stash, 'sms' );

   return $stash;
};

event_handler 'sms', '_default_' => sub {
   my ($self, $req, $stash) = @_; return $stash;
};

event_handler 'sms', '_output_' => sub {
   my ($self, $req, $stash) = @_;

   my $message = delete $stash->{message}; $message
      and $self->create_sms_job( $stash, $message );

   return;
};

# Update
event_handler 'update', '_output_' => sub {
   my ($self, $req, $stash) = @_;

   my $actionp = delete $stash->{action_path}; $actionp
      and return $self->event_component_update( $req, $stash, $actionp );

   return;
};

event_handler 'update', '_output_' => sub {
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
