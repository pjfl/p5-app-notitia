package App::Notitia::Role::Request;

use namespace::autoclean;

use Class::Usul::Constants       qw( TRUE );
use Class::Usul::Functions       qw( is_hashref );
use Class::Usul::Types           qw( HashRef Object );
use File::DataClass::Types       qw( Path );
use Try::Tiny;
use Web::ComposableRequest::Util qw( add_config_role new_uri );
use Moo::Role;

requires qw( _config _log uri_for );

add_config_role __PACKAGE__.'::Config';

has 'fs_cache' => is => 'lazy', isa => Object, required => TRUE;

has 'uri_no_query' => is => 'lazy', isa => Object, builder => sub {
   new_uri $_[ 0 ]->scheme, $_[ 0 ]->_base.$_[ 0 ]->path };

has '_state_cache' => is => 'lazy', isa => HashRef, builder => sub {
   my $self  = shift;
   my $path  = $self->_state_cache_path;
   my $cache = try { $self->fs_cache->load( $path ) } catch { {} };

   return $cache;
};

has '_state_cache_path' => is => 'lazy', isa => Path, builder => sub {
   $_[ 0 ]->_config->ctrldir->catfile( 'state-cache.json' ) };

sub uri_for_action {
   my ($self, $action, @args) = @_;

   my $uri = $self->_config->action_path2uri->( $action ) // $action;

   if (is_hashref $args[ 0 ] and exists $args[ 0 ]->{extension}) {
      my $opts = shift @args;

      $uri .= delete $opts->{extension}; push @args, $opts;
   }

   $uri =~ m{ \* }mx or return $self->uri_for( $uri, @args );

   my $args = shift @args;

   while ($uri =~ m{ \* }mx) {
      my $arg = (shift @{ $args }) || q(); $uri =~ s{ \* }{$arg}mx;
   }

   unshift @args, $args;

   return $self->uri_for( $uri, @args );
}

sub state_cache {
   my ($self, $k, $v) = @_; my $cache = $self->_state_cache;

   defined $k or return $cache;
   $self->_log->( { level => 'debug', message => "State cache key ${k}" } );
   defined $v or return $cache->{ $k };
   $self->_log->( { level => 'debug', message => "State cache value ${v}" } );

   my $storage = $self->fs_cache->storage; my $path = $self->_state_cache_path;

   return $storage->txn_do( $path, sub {
      my ($cache) = $storage->read_file( $path, TRUE );

      $cache->{ $k } = $v; $storage->write_file( $path, $cache );

      return $v;
   } );
}

package App::Notitia::Role::Request::Config;

use namespace::autoclean;

use Class::Usul::Constants qw( TRUE );
use File::DataClass::Types qw( Directory );
use Unexpected::Types      qw( CodeRef );
use Moo::Role;

has 'action_path2uri' => is => 'ro', isa => CodeRef, builder => sub { {} };

has 'ctrldir' => is => 'ro', isa => Directory, required => TRUE;

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::Request - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::Request;
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
