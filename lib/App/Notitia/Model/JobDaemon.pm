package App::Notitia::Model::JobDaemon;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL TRUE );
use App::Notitia::Form      qw( blank_form p_button p_row
                                p_select p_table p_textfield );
use App::Notitia::Util      qw( locm make_tip register_action_paths
                                to_msg uri_for_action );
use Class::Usul::Time       qw( time2str );
use Class::Usul::Types      qw( LoadableClass Object );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

# Public attributes
has '+moniker' => default => 'daemon';

has 'jobdaemon' => is => 'lazy', isa => Object, builder => sub {
   $_[ 0 ]->jobdaemon_class->new( {
      appclass => $_[ 0 ]->config->appclass, config => { name => 'jobdaemon' },
      noask => TRUE } ) };

has 'jobdaemon_class' => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default => 'App::Notitia::JobDaemon';

register_action_paths
   'daemon/status' => 'jobdaemon-status';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_button = sub {
   my ($req, $form, $action, $class) = @_;

   return p_button $form, $action, $action, {
      container_class => $class, label => locm( $req, "${action}_jobdaemon" ),
      tip => make_tip $req, "${action}_jobdaemon_tip" };
};

my $_lock_table_headers = sub {
   return [ map { { value => locm $_[ 0 ], "lock_table_header_${_}" } }
            0 .. 3 ];
};

# Private methods
my $_get_jobdaemon_status = sub {
   my ($self, $req) = @_; my $conf = $self->config;

   my $jobdaemon  = $self->jobdaemon;
   my $is_running = $jobdaemon->is_running;
   my $daemon_pid = 'N/A';
   my $start_time = 'N/A';

   if ($is_running) {
      $daemon_pid = $jobdaemon->daemon_pid;
      $start_time = time2str '%Y-%m-%d %H:%M:%S', $jobdaemon->socket_ctime;
   }

   return {
      is_running => $is_running,
      run_state  => locm( $req, $is_running ? 'Yes' : 'No' ),
      daemon_pid => $daemon_pid,
      version    => $jobdaemon->VERSION,
      start_time => $start_time,
      last_run   => $jobdaemon->last_run };
};

my $_lock_table = sub {
   my ($self, $req, $form) = @_;

   my $table = p_table $form, { headers => $_lock_table_headers->( $req ) };

   p_row $table,
      [ map { [ { value => $_->{key} },
                { value => $_->{pid} },
                { value => time2str '%Y-%m-%d %H:%M:%S', $_->{stime} },
                { value => $_->{timeout} }  ] }
           @{ $self->application->lock->list || [] } ];
   return;
};

# Public methods
sub clear_action : Role(administrator) {
   my ($self, $req) = @_; $self->jobdaemon->clear;

   my $message = [ to_msg 'Clearing job daemon locks' ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub status : Role(administrator) {
   my ($self, $req) = @_;

   my $href = uri_for_action $req, $self->moniker.'/status';
   my $form = blank_form 'jobdaemon-status', $href;
   my $page = {
      forms => [ $form ],
      selected => 'jobdaemon_status',
      title => locm $req, 'jobdaemon_status_title' };
   my $data = $self->$_get_jobdaemon_status( $req );

   p_textfield $form, 'is_running', $data->{run_state},  { disabled => TRUE };
   p_textfield $form, 'daemon_pid', $data->{daemon_pid}, { disabled => TRUE };
   p_textfield $form, 'version',    $data->{version},    { disabled => TRUE };
   p_textfield $form, 'start_time', $data->{start_time}, { disabled => TRUE };
   p_textfield $form, 'last_run',   $data->{last_run},   { disabled => TRUE };

   my $jobs = $self->schema->resultset( 'Job' )->search( {} );

   p_select $form, 'job_queue', [ map { [ $_->label ] } $jobs->all ],
      { class => 'standard-field fake-disabled',
        tip => make_tip $req, 'jobdaemon_status_job_queue_help' };

   if ($data->{is_running}) {
      $_button->( $req, $form, 'stop', 'right-last' );
      $_button->( $req, $form, 'restart', 'right' );
      $_button->( $req, $form, 'trigger', 'right' );
   }
   else {
      $self->$_lock_table( $req, $form );
      $_button->( $req, $form, 'start', 'right-last' );
      $_button->( $req, $form, 'clear', 'right' );
   }

   return $self->get_stash( $req, $page );
};

sub restart_action : Role(administrator) {
   my ($self, $req) = @_; $self->jobdaemon->restart;

   my $message = [ to_msg 'Restarting job daemon' ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub start_action : Role(administrator) {
   my ($self, $req) = @_; $self->jobdaemon->start;

   my $message = [ to_msg 'Starting job daemon' ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub stop_action : Role(administrator) {
   my ($self, $req) = @_; $self->jobdaemon->stop;

   my $message = [ to_msg 'Stopping job daemon' ];

   return { redirect => { location => $req->uri, message => $message } };
}

sub trigger_action : Role(administrator) {
   my ($self, $req) = @_; $self->jobdaemon->trigger;

   my $message = [ to_msg 'Triggering the job daemon' ];

   return { redirect => { location => $req->uri, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::JobDaemon - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::JobDaemon;
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
