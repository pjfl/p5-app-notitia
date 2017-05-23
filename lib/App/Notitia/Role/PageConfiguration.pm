package App::Notitia::Role::PageConfiguration;

use namespace::autoclean;

use App::Notitia::Constants qw( EXCEPTION_CLASS NUL TRUE );
use App::Notitia::DOM       qw( p_hidden );
use App::Notitia::Util      qw( csrf_token loc );
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Types      qw( Object );
use File::DataClass::Schema;
use Try::Tiny;
use Unexpected::Functions   qw( FailedTokenVerification );
use Web::ComposableRequest::Util qw( new_uri );
use Moo::Role;

requires qw( config execute initialise_stash load_page lock log );

has 'cache_file' => is => 'lazy', isa => Object, builder => sub {
   File::DataClass::Schema->new( {
      builder          => $_[ 0 ],
      cache_attributes => { namespace => $_[ 0 ]->config->prefix.'-state' },
      storage_class    => 'Any' } ) };

# Private methods
my $_add_form0_csrf_token = sub {
   my ($self, $req, $stash) = @_;

   my $page  = $stash->{page} or return;
   my $forms = $page->{forms} or return;
   my $form  = $forms->[ 0 ]  or return;

   $self->add_csrf_token( $req, $form );
   return;
};

my $_verify_csrf_token = sub {
   my ($self, $req) = @_;

   my $supplied = $req->body_params->( '_verify' );
   my ($salt, $token) = split m{ \- }mx, $supplied;

   $supplied eq csrf_token( $req, $salt ) or throw FailedTokenVerification;

   return;
};

# Construction
around 'execute' => sub {
   my ($orig, $self, $method, $req) = @_; my $conf = $self->config;

   my $session = $req->session; my $sess_version = $session->version;

   unless ($sess_version eq $conf->session_version) {
      $req->reset_session;
      throw 'Session version mismatch [_1] vs. [_2]. Reload page',
            [ $sess_version, $conf->session_version ];
   }

   $req->method eq 'post'
      and $conf->preferences->{verify_csrf_token}
      and $self->$_verify_csrf_token( $req );

   my $stash = $orig->( $self, $method, $req );

   $self->$_add_form0_csrf_token( $req, $stash );

   $req->authenticated and $self->activity_cache( $session->user_label );

   if (exists $stash->{redirect} and $req->authenticated and $req->referer) {
      unless ($stash->{redirect}->{location}) {
         my $location = new_uri $req->scheme, $req->referer;

         $location->query_form( {} );
         $stash->{redirect}->{location} = $location;
      }
   }

   my $key; $self->application->debug
      and $key = $self->config->appclass->env_var( 'trace' )
      and $self->application->dumper
         ( $key eq 'stash' ? $stash : $stash->{ $key } // {} );

   return $stash;
};

around 'initialise_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash  = $orig->( $self, $req, @args );
   my $params = $req->query_params;
   my $sess   = $req->session;
   my $conf   = $self->config;

   for my $k (@{ $conf->stash_attr->{session} }) {
      try {
         my $v = $params->( $k, { optional => 1 } );

         $stash->{session}->{ $k } = defined $v ? $sess->$k( $v ) : $sess->$k();
      }
      catch { $self->log->warn( $_ ) };
   }

   $stash->{application_version} = $conf->appclass->VERSION;
   $stash->{template}->{skin} = $stash->{session}->{skin};

   my $links = $stash->{links} //= {};

   for my $k (@{ $conf->stash_attr->{links} }) {
      $links->{ $k } = $req->uri_for( $conf->$k().'/' );
   }

   $links->{cdnjs   } = $conf->cdnjs;
   $links->{base_uri} = $req->base;
   $links->{req_uri } = $req->uri;

   return $stash;
};

around 'load_page' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $page = $orig->( $self, $req, @args ); my $conf = $self->config;

   for my $k (@{ $conf->stash_attr->{request} }) { $page->{ $k }   = $req->$k  }

   for my $k (@{ $conf->stash_attr->{config } }) { $page->{ $k } //= $conf->$k }

   my $skin = $req->session->skin || $conf->skin;

   $page->{template} //= [ "${skin}/menu" ];
   $page->{template}->[ 0 ] eq '/menu'
      and $page->{template}->[ 0 ] = "${skin}/menu";
   $page->{hint    } //= loc( $req, 'Hint' );
   $page->{wanted  } //=
      join '/', @{ $req->uri_params->( { optional => TRUE } ) // [] };

   return $page;
};

# Class attributes
my $_activity_cache = [];

# Public methods
sub activity_cache {
   my ($self, $v) = @_;

   defined $v and not is_member $v, $_activity_cache
      and unshift @{ $_activity_cache }, $v;

   scalar @{ $_activity_cache } > 3 and pop @{ $_activity_cache };

   return join ', ', @{ $_activity_cache };
}

sub add_csrf_token {
   my ($self, $req, $form) = @_;

   p_hidden $form, '_verify', csrf_token $req;

   return;
}

sub state_cache {
   my ($self, $k, $v) = @_;

   my $path  = $self->config->ctrldir->catfile( 'state-cache.json' );
   my $cache = try { $self->cache_file->load( $path ) } catch { {} };

   defined $k or return $cache;
   $self->log->debug( "State cache key ${k}" );
   defined $v or return $cache->{ $k };

   $cache->{ $k } = $v;
   $self->cache_file->dump( { data => $cache, path => $path } );
   return $v;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::PageConfiguration - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::PageConfiguration;
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
