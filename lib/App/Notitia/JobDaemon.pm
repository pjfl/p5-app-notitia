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
use IO::Socket::UNIX       qw( SOCK_DGRAM );
use Scalar::Util           qw( blessed );
use Try::Tiny;
use Unexpected::Functions  qw( Unspecified );
use Moo;

extends q(Class::Usul::Programs);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Override default in base class
has '+config_class' => default => 'App::Notitia::Config';

# Attribute constructors
my $_is_lock_set = sub {
   my ($self, $list, $extn) = @_; my $name = $self->config->name;

   $extn and $name = "${name}_${extn}";

   return is_member $name, map { $_->{key} } @{ $list };
};

my $_build_read_socket = sub {
   my $path = $_[ 0 ]->_socket_path;
   my $socket = IO::Socket::UNIX->new( Local => "${path}", Type => SOCK_DGRAM );

   defined $socket
      or throw 'Cannot bind to socket [_1]: [_2]', [ $path, $OS_ERROR ];

   return $socket;
};

my $_build_write_socket = sub {
   my $self = shift; my $have_warned = FALSE; my $start = time; my $socket;

   while (TRUE) {
      my $list = $self->lock->list || [];
      my $starting = $self->$_is_lock_set( $list, 'starting' );
      my $stopping = $self->$_is_lock_set( $list, 'stopping' );
      my $started = $self->$_is_lock_set( $list );
      my $exists = $self->_socket_path->exists;

      if (not $stopping and not $starting and $started and $exists) {
         $socket = IO::Socket::UNIX->new
            ( Peer => $self->_socket_path->pathname, Type => SOCK_DGRAM, );
         $socket and last;
         not $have_warned and $have_warned = TRUE and $self->log->warn
            ( 'Cannot connect to socket '.$self->_socket_path
              ." ${stopping} ${starting} ${started} ${exists} ${OS_ERROR}" );
      }

      if (time - $start > $self->max_wait) {
         my $message = 'Write socket timeout';

         $exists   or  $message = 'Socket file not found';
         $started  or  $message = 'Job daemon not started';
         $starting and $message = 'Job daemon still starting';
         $stopping and $message = 'Job daemon still stopping';
         throw "${message} [_1] [_2] [_3] [_4]",
               [ $stopping, $starting, $started, $exists ];
      }

      nap 0.5;
   }

   $self->_set_socket_ctime( $self->_socket_path->stat->{ctime} );

   return $socket;
};

my $_lower_semaphore = sub {
   my $self = shift; my $name = $self->config->name; my $buf = NUL;

   $self->read_socket->recv( $buf, 1 ) until ($buf eq 'x');

   $self->lock->reset( k => "${name}_semaphore", p => 666 );
   $self->log->debug( 'Lowered jobqueue semaphore' );
   return;
};

my $_runjob = sub {
   my ($self, $job) = @_;

   try {
      $self->log->info( 'Running job '.$job->name.'-'.$job->id );

      my $r = $self->run_cmd( [ split SPC, $job->command ] );

      $self->log->info( 'Job '.$job->name.'-'.$job->id.' rv '.$r->rv );
   }
   catch {
      my ($msg) = split m{ \n }mx, "${_}";

      $self->log->error( 'Job '.$job->name.'-'.$job->id.' rv '.$_->rv.": $msg");
   };

   return OK;
};

my $_set_started_lock = sub {
   my ($self, $lock, $name, $pid) = @_;

   unless ($lock->set( k => $name, p => $pid, t => 0, async => TRUE )) {
      try { $lock->reset( k => "${name}_starting", p => 666 ) } catch {};
      exit OK;
   }

   my $path = $self->_socket_path;
      $path->exists and $path->unlink; $path->close;

   try { $lock->reset( k => "${name}_starting", p => 666 ) } catch {};

   return;
};

my $_stdio_file = sub {
   my ($self, $extn, $name) = @_; $name //= $self->_program_name;

   return $self->file->tempdir->catfile( "${name}.${extn}" );
};

my $_daemon_loop = sub {
   my $self = shift; my $conf = $self->config; my $stopping = FALSE;

   my $last_run = $conf->tempdir->catfile( $conf->name.'_last_run' )->lock;

   while (not $stopping) {
      $self->$_lower_semaphore;

      for my $job ($self->schema->resultset( 'Job' )->search( {} )->all) {
         if ($job->command eq 'stop_jobdaemon') {
            $job->delete; $stopping = TRUE; last;
         }

         $self->run_cmd( [ sub { $_runjob->( $self, $job ) } ],
                         { async => TRUE, detach => TRUE } );

         $last_run->println( $job->name.'-'.$job->id ); $last_run->close;

         $job->delete;
      }
   }

   return;
};

my $_daemon = sub {
   my $self = shift; $PROGRAM_NAME = $self->_program_name;

   $self->log->debug( 'Trying to start the job daemon' );
   $self->config->appclass->env_var( 'debug', $self->debug );

   my $lock = $self->lock; my $name = $self->config->name; my $pid = $PID;

   $self->$_set_started_lock( $lock, $name, $pid );

   $self->log->info( "Started job daemon ${pid}" );

   my $reset = sub {
      $self->log->info( "Stopping job daemon ${pid}" );
      $self->read_socket and $self->read_socket->close;

      try { $lock->reset( k => "${name}_stopping", p => 666 ) } catch {};
      try { $lock->reset( k => "${name}_semaphore", p => 666 ) } catch {};
      try { $lock->reset( k => $name, p => $pid ) } catch {};
   };

   try { local $SIG{TERM} = sub { $reset->(); exit OK }; $self->$_daemon_loop }
   catch { $self->log->error( $_ ) };

   $reset->();

   exit OK;
};

my $_build_daemon_control = sub {
   my $self = shift; my $conf = $self->config; my $name = $conf->name;

   my $tempdir = $conf->tempdir;
   my $args    = {
      name         => blessed $self || $self,
      path         => $conf->pathname,

      directory    => $conf->appldir,
      program      => sub { shift; $self->$_daemon( @_ ) },
      program_args => [],

      pid_file     => $self->_pid_file->pathname,
      stderr_file  => $self->$_stdio_file( 'err' ),
      stdout_file  => $self->$_stdio_file( 'out' ),

      fork         => 2,
   };

   return Daemon::Control->new( $args );
};

# Public attributes
has 'max_wait' => is => 'ro', isa => PositiveInt, default => 10;

has 'read_socket' => is => 'lazy', isa => Object,
   builder => $_build_read_socket;

has 'socket_ctime' => is => 'rwp', isa => PositiveInt, builder => sub {
   my $path = $_[ 0 ]->_socket_path; $path->exists ? $path->stat->{ctime} : 0 },
   lazy => TRUE;

# Private attributes
has '_daemon_control' => is => 'lazy', isa => Object,
   builder => $_build_daemon_control;

has '_daemon_pid' => is => 'lazy', isa => PositiveInt, builder => sub {
   my $path = $_[ 0 ]->_pid_file;

   return (($path->exists && !$path->empty ? $path->getline : 0) // 0) },
   clearer => TRUE;

has '_pid_file' => is => 'lazy', isa => Path, builder => sub {
   my $file = $_[ 0 ]->config->name.'.pid';

   return $_[ 0 ]->config->rundir->catfile( $file )->chomp };

has '_program_name' => is => 'lazy', isa => NonEmptySimpleStr, builder => sub {
   return $_[ 0 ]->config->prefix.'-'.$_[ 0 ]->config->name };

has '_socket_path' => is => 'lazy', isa => Path, builder => sub {
   return $_[ 0 ]->config->tempdir->catfile( $_[ 0 ]->config->name.'.sock' ) };

has '_write_socket' => is => 'lazy', isa => Object, clearer => TRUE,
   builder => $_build_write_socket, init_arg => 'write_socket';

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

# Private methods
my $_drop_lock = sub {
   my $self = shift;

   try {
      my $pid  = $self->daemon_pid; my $name = $self->config->name;

      $self->lock->reset( k => $name, p => $pid );
      $self->log->warn( "Dropping ${name} lock ${pid}" );
   }
   catch {};

   $self->_clear_daemon_pid;
   return;
};

my $_is_write_socket_stale = sub {
   my $self = shift; my $list = $self->lock->list || [];

   $self->$_is_lock_set( $list, 'starting' ) and return TRUE;
   $self->$_is_lock_set( $list, 'stopping' ) and return TRUE;

   my $path = $self->_socket_path; $path->exists or return TRUE;

   return $path->stat->{ctime} > $self->socket_ctime ? TRUE : FALSE;
};

my $_raise_semaphore = sub {
   my $self = shift;
   my $name = $self->config->name;
   my $socket = $self->write_socket or throw 'No write socket';

   $self->lock->set( k => "${name}_semaphore", p => 666, async => TRUE )
      or return FALSE;

   $socket->send( 'x' );

   return TRUE;
};

# Public methods
sub clear : method {
   my $self = shift; $self->is_running and throw 'Cannot clear whilst running';

   my $pid = $self->daemon_pid; my $name = $self->config->name;

   try { $self->lock->reset( k => "${name}_semaphore", p => 666 ) } catch {};
   try { $self->lock->reset( k => "${name}_starting",  p => 666 ) } catch {};
   try { $self->lock->reset( k => "${name}_stopping",  p => 666 ) } catch {};
   try { $self->lock->reset( k => $name, p => $pid ) } catch {};

   $self->_pid_file->exists and $self->_pid_file->unlink;

   return OK;
}

sub daemon_pid {
   my $self = shift; my $pid = $self->_daemon_pid;

   $pid == 0 and $self->_clear_daemon_pid;
   $pid == 0 and $pid = $self->_daemon_pid;

   return $pid;
}

sub is_running {
   return $_[ 0 ]->_daemon_control->pid_running ? TRUE : FALSE;
}

sub restart : method {
   my $self = shift; $self->params->{restart} = [ { expected_rv => 1 } ];

   $self->lock->set( k => $self->config->name.'_stopping', p => 666 );

   $self->daemon_pid;
   $self->_daemon_control->pid_running and $self->_daemon_control->do_stop;
   $self->daemon_pid and $self->$_drop_lock;

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

   my $name = $self->config->name; my $stopping;

   while (not defined $stopping or $stopping) {
      $stopping = $self->$_is_lock_set( $self->lock->list, 'stopping' );
      $stopping and nap 0.5
   }

   $self->lock->set( k => "${name}_starting", p => 666 );

   my $rv = $self->_daemon_control->do_start;

   $rv == OK and $self->$_raise_semaphore
      and $self->log->debug( 'Raised jobqueue semaphore on startup' );

   return $rv;
}

sub status : method {
   my $self = shift; $self->params->{status} = [ { expected_rv => 3 } ];

   return $self->_daemon_control->do_status;
}

sub stop : method {
   my $self = shift; $self->params->{stop} = [ { expected_rv => 1 } ];

   $self->lock->set( k => $self->config->name.'_stopping', p => 666 );

   $self->daemon_pid; my $rv = $self->_daemon_control->do_stop;

   $self->daemon_pid and $self->$_drop_lock;

   return $rv;
}

sub trigger : method {
   $_[ 0 ]->$_raise_semaphore; return OK;
}

sub write_socket {
   my $self = shift;

   $self->$_is_write_socket_stale and $self->_clear_write_socket;

   return $self->_write_socket;
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

=head2 C<clear> - Clears left over locks in the event of failure

Clears left over locks in the event of failure

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
