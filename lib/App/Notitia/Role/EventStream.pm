package App::Notitia::Role::EventStream;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE OK SPC TRUE );
use App::Notitia::Util      qw( event_handler event_handler_cache );
use Class::Usul::File;
use Class::Usul::Functions  qw( create_token is_member throw );
use Class::Usul::Log        qw( get_logger );
use Class::Usul::Types      qw( HashRef Object );
use Try::Tiny;
use Unexpected::Functions   qw( catch_class Disabled );
use Web::Components::Util   qw( load_components );
use Moo::Role;

requires qw( components config schema );

my $_plugins_cache;

has 'plugins' => is => 'lazy', isa => HashRef[Object], builder => sub {
   my $self = shift; defined $_plugins_cache and return $_plugins_cache;

   return $_plugins_cache = load_components 'Plugin',
      application => $self->can( 'application' ) ? $self->application : $self;
};

# Private functions
my $_clean_and_log = sub {
   my ($req, $message) = @_; $message ||= 'action:unknown';

   my $user = $req->username || 'admin';
   my $address = $req->address || 'localhost';

   $message = "user:${user} client:${address} ${message}";

   get_logger( 'activity' )->log( $message );

   return $message;
};

# Private methods
my $_session_file = sub {
   return $_[ 0 ]->config->sessdir->catfile( substr create_token, 0, 32 );
};

my $_flatten_stash = sub {
   my ($self, $v) = @_; my $path = $self->$_session_file;

   my $params = { data => $v, path => $path->assert, storage_class => 'JSON' };

   Class::Usul::File->data_dump( $params );

   return "-o stash=${path} ";
};

my $_inflate = sub {
   my ($self, $req, $message, $sink) = @_;

   my $stash = {
      app_name => $self->config->title, message => $message, sink => $sink };

   for my $pair (split SPC, $message) {
      my ($k, $v) = split m{ : }mx, $pair;

      exists $stash->{ $k } or $stash->{ $k } = $v;
   }

   $stash->{action}
      or throw 'Message contains no action: [_1]', [ $message ], level => 2;
   $stash->{action} =~ s{ [\-] }{_}gmx;

   return $stash;
};

# Public methods
sub create_email_job {
   my ($self, $stash, $template) = @_; my $conf = $self->config;

   my $cmd = $conf->binsdir->catfile( 'notitia-schema' ).SPC
           . $self->$_flatten_stash( $stash )."send_message email ${template}";
   my $rs  = $self->schema->resultset( 'Job' );

   return $rs->create( { command => $cmd, name => 'send_message' } );
}

sub dump_event_attr : method {
   my $self = shift; $self->plugins;

   $self->dumper( event_handler_cache );

   return OK;
}

sub event_model_update {
   my ($self, $req, $stash, $moniker, $method) = @_;

   my $compo = $self->components->{ $moniker }
      or throw 'Model moniker [_1] unknown', [ $moniker ], level => 2;

   $compo->can( $method ) or
      throw 'Model [_1] has no method [_2]', [ $moniker, $method ], level => 2;

   $compo->$method( $req, $stash );
   return;
}

sub send_event {
   my ($self, $req, $message) = @_; $self->plugins;

   $message = $_clean_and_log->( $req, $message ); my $conf = $self->config;

   for my $sink_name (keys %{ $conf->automated }) {
      try {
         my $stash = $self->$_inflate( $req, $message, $sink_name );
         my $buildargs = event_handler( 'buildargs', $sink_name )->[ 0 ];

         $buildargs and $stash = $buildargs->( $self, $req, $stash );
         is_member $stash->{action}, $conf->automated->{ $sink_name }
            or throw Disabled, [ $sink_name, $stash->{action} ];

         for my $args (@{ event_handler( $sink_name, $stash->{action} ) }) {
            for my $sink (@{ event_handler( 'sink', $sink_name ) }) {
               $sink->( $self, $req, $args->( $self, $req, { %{ $stash } } ) );
            }
         }
      }
      catch_class [
         Disabled => sub { $self->log->debug( $_ ) },
         '*'      => sub { $self->log->error( $_ ) },
      ];
   }

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

=head2 C<dump_event_attr> - Dumps the event handling attribute data

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
