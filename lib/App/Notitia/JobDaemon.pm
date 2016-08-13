package App::Notitia::JobDaemon;

use namespace::autoclean;

use App::Notitia; our $VERSION = $App::Notitia::VERSION;

use Class::Usul::Constants qw( EXCEPTION_CLASS NUL OK SPC TRUE );
use Class::Usul::Functions qw( get_user throw );
use Class::Usul::Types     qw( ArrayRef NonEmptySimpleStr );
use Daemon::Control;
use English                qw( -no_match_vars );
use Scalar::Util           qw( blessed );
use Try::Tiny;
use Unexpected::Functions  qw( Unspecified );
use Moo;

extends q(Class::Usul::Schema);
with    q(App::Notitia::Role::Schema);

# Override default in base class
has '+config_class'   => default => 'App::Notitia::Config';

has '+database'       => default => sub { $_[ 0 ]->config->database };

has '+schema_classes' => default => sub { $_[ 0 ]->config->schema_classes };

has '+schema_version' => default => sub { App::Notitia->schema_version.NUL };

# Public attributes
has 'program_name' => is => 'ro',   isa => NonEmptySimpleStr,
   default         => 'notitia-jobdaemon';

has 'read_socket'  => is => 'lazy', isa => ,
   builder         => sub { $_[ 0 ]->_socket_pair->[ 0 ] };

has 'write_socket' => is => 'lazy', isa => ,
   builder         => sub { $_[ 0 ]->_socket_pair->[ 1 ] };

# Private attributes
has '_socket_pair' => is => 'lazy', isa => ArrayRef,
   builder         => sub {};

# Private methods
my $_lower_semaphore = sub {
   my $self = shift; my $buf; my $red = $self->read_socket->read( $buf, 1 );

   $red == 1 and $buf eq 'x' and $self->lock->reset( k => 'semaphore' );

   return;
};

my $_raise_semaphore = sub {
   my $self = shift;
   my $lock = $self->lock->set( k => 'semaphore', async => TRUE );

   $lock and $self->write_socket->write( 'x', 1 );

   return $lock;
};

my $_runjob = sub {
   my ($self, $job) = @_;

   try {
      $self->info( 'Running job [_1]-[_2]',
                   { args => [ $job->name, $job->id ] } );

      my $r = $self->run_cmd( [ split SPC, $job->command ] );

      $self->info( 'Job [_1]-[_2] rv [_3]',
                   { args => [ $job->name, $job->id, $r->rv ] } );
   }
   catch {
      my ($summary) = split m{ \n }mx, "${_}";

      $self->error( 'Job [_1]-[_2] rv [_3]: [_4]',
                    { args => [ $job->name, $job->id, $_->rv, $summary ],
                      no_quote_bind_values => TRUE } );
   };

   return;
};

my $_stdio_file = sub {
   my ($self, $extn, $name) = @_; $name //= $self->program_name;

   return $self->file->tempdir->catfile( "${name}.${extn}" );
};

my $_daemon = sub {
   my $self = shift; $PROGRAM_NAME = $self->program_name;

   $self->config->appclass->env_var( 'debug', $self->debug );

   my $lock = $self->lock->set( k => 'runqueue', async => TRUE );

   $lock or exit OK; my $stopping = FALSE;

   $self->$_raise_semaphore
      and $self->log->debug( 'Raised jobqueue semaphore on startup' );

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

   $self->lock->reset( k => 'runqueue' );

   exit OK;
};

# Attribute construction
my $_build_daemon_control = sub {
   my $self = shift; my $conf = $self->config; my $name = $conf->name;

   my $tempdir = $conf->tempdir;
   my $args    = {
      name         => blessed $self || $self,
      lsb_start    => '$syslog $remote_fs',
      lsb_stop     => '$syslog',
      lsb_sdesc    => 'Scheduler',
      lsb_desc     => 'People and resource scheduling server daemon',
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
sub raise_semaphore {
   return $_[ 0 ]->$_raise_semaphore;
}

sub restart : method {
   my $self = shift; $self->params->{restart} = [ { expected_rv => 1 } ];

   return $self->_daemon_control->do_restart;
}

sub show_warnings : method {
   $_[ 0 ]->_daemon_control->do_show_warnings; return OK;
}

sub start : method {
   my $self = shift; $self->params->{start} = [ { expected_rv => 1 } ];

   return $self->_daemon_control->do_start;
}

sub status : method {
   my $self = shift; $self->params->{status} = [ { expected_rv => 3 } ];

   return $self->_daemon_control->do_status;
}

sub stop : method {
   my $self = shift; $self->params->{stop} = [ { expected_rv => 1 } ];

   my $rv = $self->_daemon_control->do_stop;

   $self->lock->reset( k => 'runqueue' );
   $self->lock->reset( k => 'semaphore' );
   return $rv;
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
