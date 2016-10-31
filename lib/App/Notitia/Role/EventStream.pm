package App::Notitia::Role::EventStream;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL OK SPC TRUE );
use App::Notitia::Util      qw( event_handler event_handler_cache );
use Class::Usul::File;
use Class::Usul::Functions  qw( create_token is_member throw trim );
use Class::Usul::Log        qw( get_logger );
use Class::Usul::Types      qw( HashRef Object );
use Try::Tiny;
use Unexpected::Functions   qw( catch_class Disabled Unspecified );
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
   my ($req, $message, $params) = @_;

   $message ||= 'message:blank'; $params //= {};

   my $user = $req->username || 'admin';
   my $address = $req->address || 'localhost';

   $message = "user:${user} client:${address} ${message}";
   exists $params->{level} and $message .= ' level:'.$params->{level};
   get_logger( 'activity' )->log( $message );

   return $message;
};

my $_flatten = sub {
   my $stash = shift; my $message = NUL;

   for my $k (sort keys %{ $stash }) { $message .= " ${k}:".$stash->{ $k } }

   return trim $message;
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
   my ($self, $req, $message) = @_;

   my $stash = { app_name => $self->config->title, message => $message };

   for my $pair (split SPC, $message) {
      my ($k, $v) = split m{ : }mx, $pair;

      exists $stash->{ $k } or $stash->{ $k } = $v;
   }

   $stash->{action} and $stash->{action} =~ s{ [\-] }{_}gmx;
   $stash->{level} ||= 0; $stash->{level}++;

   return $stash;
};

my $_is_valid_message = sub {
   my ($self, $req, $message) = @_;

   my $inflated = $self->$_inflate( $req, $message );

   unless ($inflated->{action}) {
      $self->log->error( "Message contains no action: ${message}" ); return;
   }

   my $max_levels = $self->config->automated->{_max_levels} // 10;

   if ($inflated->{level} > $max_levels) {
      $self->log->error
         ( "Maximum send_event recursion levels ${max_levels} reached" );
      return;
   }

   return $inflated;
};

my $_make_template = sub {
   my ($self, $message) = @_;

   my $path = $self->$_session_file; $path->println( trim $message );

   return $path;
};

# Public methods
sub create_email_job {
   my ($self, $stash, $template) = @_; my $conf = $self->config;

   my $cmd = $conf->binsdir->catfile( 'notitia-schema' ).SPC
           . $self->$_flatten_stash( $stash )."send_message email ${template}";
   my $rs  = $self->schema->resultset( 'Job' );

   return $rs->create( { command => $cmd, name => 'send_message' } );
}

sub create_sms_job {
   my ($self, $stash, $message) = @_; my $conf = $self->config;

   my $path = $self->$_make_template( $message );
   my $cmd  = $conf->binsdir->catfile( 'notitia-schema' ).SPC
            . $self->$_flatten_stash( $stash )."send_message sms ${path}";
   my $rs   = $self->schema->resultset( 'Job' );

   return $rs->create( { command => $cmd, name => 'send_message' } );
}

sub dump_event_attr : method {
   my $self = shift; $self->plugins; my $cache = event_handler_cache;

   if ($self->options->{not_enabled}) {
      for my $sink_name (keys %{ $cache }) {
         my $allowed = $self->config->automated->{ $sink_name };
         my @keys = keys %{ $cache->{ $sink_name } };

         for my $action (@keys) {
            ($action =~ m{ \A _ }mx or is_member $action, $allowed)
               and delete $cache->{ $sink_name }->{ $action };
         }
      }
   }

   $self->dumper( $cache );
   return OK;
}

sub event_component_update {
   my ($self, $req, $stash, $actionp) = @_;

   my ($moniker, $method) = split m{ / }mx, $actionp;

   $method or throw Unspecified, [ 'update method' ];

   my $component = $self->components->{ $moniker }
      or throw 'Model moniker [_1] unknown', [ $moniker ];

   $component->can( $method ) or
      throw 'Model [_1] has no method [_2]', [ $moniker, $method ];

   $component->$method( $req, $stash );
   return;
}

sub event_schema_update {
   my ($self, $req, $stash, $resultp) = @_;

   my ($class, $method) = split m{ / }mx, $resultp;

   $method or throw Unspecified, [ 'update method' ];

   my $rs = $self->schema->resultset( $class );
   my $message = delete $stash->{message};

   if    ($method eq 'create') { $rs->create( $stash ) }
   elsif ($method eq 'delete' or $method eq 'update') {
      my $key = delete $stash->{key} or throw Unspecified, [ 'key' ];
      my $row = $rs->find( $key );

      defined $row or throw 'Class [_1] key [_2] not found', [ $class, $key ];

      if ($method eq 'delete') { $row->delete }
      else { $row->update( $stash ) }
   }
   else { throw 'Method [_1] unknown', [ $method ] }

   return $message;
}

sub send_event {
   my ($self, $req, $message, $params) = @_; my $conf = $self->config;

   $self->plugins; $message = $_clean_and_log->( $req, $message, $params );

   my $inflated = $self->$_is_valid_message( $req, $message ) or return;

   for my $sink_name (grep { not m{ \A _ }mx } keys %{ $conf->automated }) {
      try {
         my $stash = { %{ $inflated } };
         my $level = delete $stash->{level}; $stash->{sink} = $sink_name;
         my $buildargs = event_handler( $sink_name, '_buildargs_' )->[ 0 ];

         $buildargs and $stash = $buildargs->( $self, $req, $stash );

         my $action = $stash->{action};

         is_member $action, $conf->automated->{ $sink_name }
            or throw Disabled, [ $sink_name, $action ];

         for my $handler (@{ event_handler( $sink_name, $action ) }) {
            my $processed = $handler->( $self, $req, { %{ $stash } } ) or next;

            for my $sink (@{ event_handler( $sink_name, '_sink_' ) }) {
               my $chained = $sink->( $self, $req, { %{ $processed } } );

               $chained and $chained->{level} = $level
                  and $self->send_event( $req, $_flatten->{ $chained } );
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
