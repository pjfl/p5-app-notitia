package App::Notitia::Model;

use App::Notitia::Attributes qw( is_dialog ); # Will do namespace cleaning
use App::Notitia::Constants  qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use App::Notitia::Form       qw( blank_form f_tag p_tag );
use App::Notitia::Util       qw( action_for_uri locm to_json uri_for_action );
use Class::Usul::Functions   qw( exception is_member throw trim );
use Class::Usul::Time        qw( time2str );
use Class::Usul::Types       qw( Plinth );
use HTTP::Status             qw( HTTP_NOT_FOUND HTTP_OK );
use Scalar::Util             qw( blessed );
use Try::Tiny;
use Unexpected::Functions    qw( Authentication AuthenticationRequired
                                 IncorrectPassword IncorrectAuthCode
                                 ValidationErrors );
use Moo;

with q(Web::Components::Role);
with q(Class::Usul::TraitFor::ConnectInfo);
with q(App::Notitia::Role::Schema);
with q(App::Notitia::Role::EventStream);

# Public attributes
has 'application' => is => 'ro', isa => Plinth,
   required       => TRUE,  weak_ref => TRUE;

# Class attributes
my $_activity_cache = [];

# Private functions
my $_collect_status_messages = sub {
   my $req = shift; my @messages = ();

   my $mid = $req->query_params->( 'mid', { optional => TRUE } )
      or return \@messages;

   my $session = $req->session;
   my @keys = reverse sort keys %{ $session->messages };

   while (my $key = $keys[ 0 ]) {
      $key gt $mid and next; my $msg = delete $session->messages->{ $key };

      push @messages, $req->loc( @{ $msg } ); shift @keys;
   }

   return \@messages;
};

my $_debug_output = sub {
   my ($req, $e, $form, $leader) = @_;

   my $line1 = 'Exception thrown ';
   my $when  = time2str 'on %Y-%m-%d at %H:%M hours', $e->time;

   if ($leader) {
      $line1 .= "from ${leader}"; p_tag $form, 'p', "${line1}<br>${when}";
   }
   else { p_tag $form, 'p', "${line1} ${when}" }

   p_tag $form, 'h6', 'HTTP status code&nbsp;'.$e->code;
   p_tag $form, 'h6', 'Have a nice day...';
   return;
};

my $_parse_error = sub {
   my $e = shift; my ($leader, $message, $summary);

   if ($e =~ m{ : }mx) {
      ($leader, $message) = split m{ : }mx, "${e}", 2;
      $summary = substr trim( $message ), 0, 500;
   }
   else { $leader = NUL; $summary = $message = "${e}" }

   return $leader, $message, $summary;
};

my $_validation_errors = sub {
   my ($req, $e, $form) = @_;

   p_tag $form, 'h5', locm $req, 'Form validation errors';

   for my $message (map { ($_parse_error->( $_ ))[ 1 ] } @{ $e->args }) {
      p_tag $form, 'p', $message;
   }

   return;
};

# Private methods
my $_auth_redirect = sub {
   my ($self, $req, $e, $message) = @_; my $class = $e->class;

   my $location = uri_for_action $req, $self->config->places->{login};

   if ($class eq IncorrectPassword->() or $class eq IncorrectAuthCode->()) {
      $self->send_event( $req, 'action:failed-login' );
   }

   if ($class eq AuthenticationRequired->()) {
      my $wanted = $req->path || NUL; my $actionp = action_for_uri $wanted;

      (($actionp and not is_dialog $self->components, $actionp)
       or (not $actionp and $wanted)) and $req->session->wanted( $wanted );

      return { redirect => { location => $location, message => [ $message ] } };
   }

   if ($e->instance_of( Authentication->() )) {
      return { redirect => { location => $location, message => [ $message ] } };
   }

   return;
};

# Public methods
sub activity_cache {
   my ($self, $v) = @_;

   defined $v and not is_member $v, $_activity_cache
      and unshift @{ $_activity_cache }, $v;

   scalar @{ $_activity_cache } > 3 and pop @{ $_activity_cache };

   return join ', ', @{ $_activity_cache };
}

sub blow_smoke {
   my ($self, $e, $verb, $noun, $label) = @_;

   $self->application->debug and throw $e;
   $e->can( 'class' ) and $e->class eq ValidationErrors->() and throw $e;
   $e =~ m{ duplicate }imx and throw 'Duplicate [_1] [_2]', [ $noun, $label ],
                                     no_quote_bind_values => TRUE;
   $self->log->error( $e );
   throw 'Failed to [_1] [_2] [_3]', [ $verb, $noun, $label ],
         no_quote_bind_values => TRUE;
}

sub dialog_stash {
   my ($self, $req, $layout) = @_;

   my $stash = $self->initialise_stash( $req ); my $id;

   try { $id = $req->query_params->( 'id' ) } catch { $self->log->error( $_ ) };

   $id or return $stash;

   $stash->{page} = $self->load_page( $req, {
      fields => {}, meta => { id => $id, }, } );
   $stash->{template}->{layout} = $layout // 'dialog';
   $stash->{template}->{skin} = $req->session->skin || $self->config->skin;
   $stash->{view} = 'json';

   return $stash;
}

sub exception_handler {
   my ($self, $req, $e) = @_;

   my ($leader, $message, $summary) = $_parse_error->( $e );

   my $redirect = $self->$_auth_redirect( $req, $e, $summary );
      $redirect and return $redirect;

   my $name = $req->session->first_name || $req->username || 'unknown';
   my $form = blank_form { type => 'list' };
   my $page = { forms => [ $form ], template => [ 'none', NUL ],
                title => locm $req, 'Exception Handler', $name };
   my $stash = $self->get_stash( $req, $page );

   if ($e->class eq ValidationErrors->()) {
      $_validation_errors->( $req, $e, $form );
   }
   else {
      p_tag $form, 'h5', locm $req, 'The following exception was thrown';
      p_tag $form, 'p', $summary;
   }

   $self->application->debug and $_debug_output->( $req, $e, $form, $leader );

   $stash->{code} = $e->code > HTTP_OK ? $e->code : HTTP_OK;

   return $stash;
}

sub execute {
   my ($self, $method, @args) = @_;

   $self->can( $method ) and return $self->$method( @args );

   throw 'Class [_1] has no method [_2]', [ blessed $self, $method ];
}

sub get_stash {
   my ($self, $req, $page) = @_;

   my $stash = $self->initialise_stash( $req );

   $stash->{page} = $self->load_page( $req, $page );

   $stash->{page}->{status_messages}
      = to_json $_collect_status_messages->( $req );

   return $stash;
}

sub initialise_stash {
   return { code => HTTP_OK, view => $_[ 0 ]->config->default_view, };
}

sub jobdaemon {
   return $_[ 0 ]->components->{daemon}->jobdaemon;
}

sub load_page {
   my ($self, $req, $page) = @_; $page //= {}; return $page;
}

sub not_found : Role(anon) {
   my ($self, $req) = @_;

  (my $mp   = $self->config->mount_point) =~ s{ \A / \z }{}mx;
   my $want = join '/', $mp, $req->path;
   my $e    = exception 'URI [_1] not found', [ $want ], rv => HTTP_NOT_FOUND;

   return $self->exception_handler( $req, $e );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model;
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
