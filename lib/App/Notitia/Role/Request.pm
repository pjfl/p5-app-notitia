package App::Notitia::Role::Request;

use namespace::autoclean;

use App::Notitia::Util           qw( action_path2uri );
use Class::Usul::Constants       qw( TRUE );
use Class::Usul::Functions       qw( is_hashref );
use Class::Usul::Types           qw( HashRef Object );
use File::DataClass::Types       qw( Path );
use Try::Tiny;
use Web::ComposableRequest::Util qw( add_config_role new_uri );
use Moo::Role;

requires qw( _config _log uri_for );

add_config_role __PACKAGE__.'::Config';

# Public attributes
has 'fs_cache' => is => 'lazy', isa => Object, required => TRUE;

has 'uri_no_query' => is => 'lazy', isa => Object, builder => sub {
   new_uri $_[ 0 ]->scheme, $_[ 0 ]->_base.$_[ 0 ]->path };

# Private attributes
has '_state_cache' => is => 'lazy', isa => HashRef, builder => sub {
   my $self  = shift;
   my $path  = $self->_state_cache_path;
   my $cache = try { $self->fs_cache->load( $path ) } catch { {} };

   return $cache;
};

has '_state_cache_path' => is => 'lazy', isa => Path, builder => sub {
   $_[ 0 ]->_config->ctrldir->catfile( 'state-cache.json' ) };

# Public methods
sub uri_for_action {
   my ($self, $action, $args, @params) = @_;

   my $uri    = action_path2uri( $action ) // $action;
   my $params = is_hashref $params[ 0 ] ? $params[ 0 ] : { @params };

   exists $params->{extension} and $uri .= delete $params->{extension};

   while ($uri =~ m{ \* }mx) {
      my $arg = (shift @{ $args }) || q(); $uri =~ s{ \* }{$arg}mx;
   }

   return $self->uri_for( $uri, $args, $params );
}

sub state_cache {
   my ($self, $k, $v) = @_; my $cache = $self->_state_cache;

   defined $k or return $cache;
   $self->_log->( { level => 'debug', message => "State cache key ${k}" } );
   defined $v or return $cache->{ $k };
   $self->_log->( { level => 'debug', message => "State cache value ${v}" } );

   my $storage = $self->fs_cache->storage; my $path = $self->_state_cache_path;

   return $cache->{ $k } = $storage->txn_do( $path, sub {
      $path->exists or $path->touch;

      my ($cache) = $storage->read_file( $path, TRUE );

      $cache->{ $k } = $v; $storage->write_file( $path, $cache );

      return $v;
   } );
}

package App::Notitia::Role::Request::Config;

use namespace::autoclean;

use Class::Usul::Constants qw( TRUE );
use File::DataClass::Types qw( Directory );
use Moo::Role;

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
