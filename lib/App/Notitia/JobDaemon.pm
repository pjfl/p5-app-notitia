package App::Notitia::JobDaemon;

use namespace::autoclean;

use App::Notitia; our $VERSION = $App::Notitia::VERSION;

use Class::Usul::Constants qw( COMMA EXCEPTION_CLASS FALSE NUL OK SPC TRUE );
use Class::Usul::Functions qw( emit get_user is_member throw );
use Class::Usul::Time      qw( nap time2str );
use Class::Usul::Types     qw( NonEmptySimpleStr Object PositiveInt );
use Daemon::Control;
use English                qw( -no_match_vars );
use File::DataClass::Types qw( Path );
use IO::Socket::UNIX       qw( SOCK_DGRAM SOCK_STREAM SOMAXCONN );
use Scalar::Util           qw( blessed );
use Try::Tiny;
use Unexpected::Functions  qw( Unspecified );
use Moo;

extends q(Class::Usul::Programs);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Override default in base class
has '+config_class'   => default => 'App::Notitia::Config';

# Attribute constructors
my $_build_read_socket = sub {
   return  IO::Socket::UNIX->new
      ( Local => $_[ 0 ]->_socket_path->pathname, Type => SOCK_DGRAM, );
};

my $_build_write_socket = sub {
   my $self = shift; my $name = $self->config->name; my $start = time;

   my $socket;

   while (TRUE) {
      my $pid = $self->_daemon_pid;
      my $list = $self->lock->list || [];
      my $lock = is_member $name, map { $_->{key} } @{ $list };
      my $exists = $self->_socket_path->exists;

      if ($pid and $lock and $exists) {
         $socket = IO::Socket::UNIX->new
            ( Peer => $self->_socket_path->pathname, Type => SOCK_DGRAM, );
         $socket and last;
      }

      time - $start > $self->max_wait and
         throw 'Write socket timeout [_1] [_2] [_3]', [ $pid, $lock, $exists ];
      $self->_clear_daemon_pid;
      nap 0.25;
   }

   return $socket;
};

# Public attributes
has 'max_wait'     => is => 'ro',   isa => PositiveInt, default => 10;

has 'read_socket'  => is => 'lazy', isa => Object,
   builder         => $_build_read_socket;

has 'write_socket' => is => 'lazy', isa => Object,
   builder         => $_build_write_socket;

# Private attributes
has '_daemon_pid'   => is => 'lazy', isa => PositiveInt, builder => sub {
   my $file = $_[ 0 ]->config->name.'.pid';
   my $path = $_[ 0 ]->config->rundir->catfile( $file )->chomp;

   return $path->exists ? $path->getline : 0; }, clearer => TRUE;

has '_program_name' => is => 'lazy', isa => NonEmptySimpleStr, builder => sub {
   return $_[ 0 ]->config->prefix.'-'.$_[ 0 ]->config->name };

has '_socket_path'  => is => 'lazy', isa => Path, builder => sub {
   return $_[ 0 ]->config->tempdir->catfile( $_[ 0 ]->config->name.'.sock' ) };

# Private methods
my $_drop_lock = sub {
   my $self = shift;

   my $pid  = $self->_daemon_pid; my $name = $self->config->name;

   try { $self->lock->reset( k => $name, p => $pid ) } catch {};

   $self->log->info( "Stopping job daemon ${pid}" );
   $self->_clear_daemon_pid;
   return;
};

my $_lower_semaphore = sub {
   my $self = shift; my $pid = $self->_daemon_pid; my $buf = NUL;

   $self->read_socket->recv( $buf, 1 ) until ($buf eq 'x');

   $self->lock->reset( k => 'jobqueue_semaphore', p => $pid );
   $self->log->debug( 'Lowered jobqueue semaphore' );
   return;
};

my $_raise_semaphore = sub {
   my $self = shift; my $pid = $self->_daemon_pid;

   $self->lock->set( k => 'jobqueue_semaphore', p => $pid, async => TRUE )
      or return FALSE;

   $self->write_socket->send( 'x' );

   return TRUE;
};

my $_runjob = sub {
   my ($self, $job) = @_;

   try {
      $self->log->info( 'Running job [_1]-[_2]',
                        { args => [ $job->name, $job->id ] } );

      my $r = $self->run_cmd( [ split SPC, $job->command ] );

      $self->log->info( 'Job [_1]-[_2] rv [_3]',
                        { args => [ $job->name, $job->id, $r->rv ] } );
   }
   catch {
      my ($summary) = split m{ \n }mx, "${_}";

      $self->log->error( 'Job [_1]-[_2] rv [_3]: [_4]',
                         { args => [ $job->name, $job->id, $_->rv, $summary ],
                           no_quote_bind_values => TRUE } );
   };

   return;
};

my $_stdio_file = sub {
   my ($self, $extn, $name) = @_; $name //= $self->_program_name;

   return $self->file->tempdir->catfile( "${name}.${extn}" );
};

my $_daemon = sub {
   my $self = shift; $PROGRAM_NAME = $self->_program_name;

   $self->log->debug( 'Trying to start the job daemon' );
   $self->config->appclass->env_var( 'debug', $self->debug );

   my $pid  = $self->_daemon_pid; my $name = $self->config->name;

   my $lock = $self->lock->set( k => $name, p => $pid, async => TRUE );

   $lock or exit OK; my $stopping = FALSE; $self->_socket_path->unlink;

   $self->log->info( "Started job daemon ${pid}" );

   while (not $stopping) {
      $self->$_lower_semaphore;

      for my $job ($self->schema->resultset( 'Job' )->search( {} )->all) {
         if ($job->command eq 'stop_jobdaemon') {
            $job->delete; $stopping = TRUE; last;
         }

         $self->run_cmd( sub { $_runjob->( $self, $job ) }, { async => TRUE } );
         $job->delete;
      }
   }

   $self->read_socket->close; $self->lock->reset( k => $name, p => $pid );

   exit OK;
};

# Attribute construction
my $_build_daemon_control = sub {
   my $self = shift; my $conf = $self->config; my $name = $conf->name;

   my $tempdir = $conf->tempdir;
   my $args    = {
      name         => blessed $self || $self,
      path         => $conf->pathname,

      directory    => $conf->appldir,
      program      => sub { shift; $self->$_daemon( @_ ) },
      program_args => [],

      pid_file     => $conf->rundir->catfile( "${name}.pid" ),
      stderr_file  => $self->$_stdio_file( 'err' ),
      stdout_file  => $self->$_stdio_file( 'out' ),

      fork         => 2,
   };

   return Daemon::Control->new( $args );
};

# Private attributes
has '_daemon_control' => is => 'lazy', isa => Object,
   builder            => $_build_daemon_control;

# Construction
around 'run' => sub {
   my ($orig, $self) = @_; my $daemon = $self->_daemon_control;

   $daemon->name     or throw Unspecified, [ 'name'     ];
   $daemon->program  or throw Unspecified, [ 'program'  ];
   $daemon->pid_file or throw Unspecified, [ 'pid file' ];

   $daemon->uid and not $daemon->gid
                and $daemon->gid( get_user( $daemon->uid )->gid );

   $self->quiet( TRUE );

   return $orig->( $self );
};

# Public methods
sub is_running {
   return $_[ 0 ]->_daemon_control->pid_running ? TRUE : FALSE;
}

sub restart : method {
   my $self = shift; $self->params->{restart} = [ { expected_rv => 1 } ];

   $self->_daemon_pid; $self->_daemon_control->read_pid;

   $self->_daemon_control->pid_running and $self->_daemon_control->do_stop;

   $self->_daemon_pid and $self->$_drop_lock;

   return $self->start;
}

sub show_locks : method {
   my $self = shift;

   for my $ref (@{ $self->lock->list || [] }) {
      my $stime = time2str '%Y-%m-%d %H:%M:%S', $ref->{stime};

      emit join COMMA, $ref->{key}, $ref->{pid}, $stime, $ref->{timeout};
   }

   return OK;
}

sub show_warnings : method {
   $_[ 0 ]->_daemon_control->do_show_warnings; return OK;
}

sub start : method {
   my $self = shift; $self->params->{start} = [ { expected_rv => 1 } ];

   my $rv = $self->_daemon_control->do_start;

   $rv == OK and $self->write_socket and $self->$_raise_semaphore
      and $self->log->debug( 'Raised jobqueue semaphore on startup' );

   return $rv;
}

sub status : method {
   my $self = shift; $self->params->{status} = [ { expected_rv => 3 } ];

   return $self->_daemon_control->do_status;
}

sub stop : method {
   my $self = shift; $self->params->{stop} = [ { expected_rv => 1 } ];

   $self->_daemon_pid; my $rv = $self->_daemon_control->do_stop;

   $self->_daemon_pid and $self->$_drop_lock;

   return $rv;
}

sub trigger : method {
   $_[ 0 ]->$_raise_semaphore; return OK;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::JobDaemon - People and resource scheduling

=head1 Synopsis

   use App::Notitia::JobDaemon;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head2 C<restart> - Restart the server

Restart the server

=head2 C<show_locks> - Show the contents of the lock table

Show the contents of the lock table

=head2 C<show_warnings> - Show server warnings

Show server warnings

=head2 C<start> - Start the server

Start the server

=head2 C<status> - Show the current server status

Show the current server status

=head2 C<stop> - Stop the server

Stop the server

=head2 C<trigger> - Triggers the dequeueing process

Triggers the dequeueing process

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
