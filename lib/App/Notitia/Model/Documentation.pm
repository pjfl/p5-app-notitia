package App::Notitia::Model::Documentation;

use App::Notitia::Attributes;  # Will do cleaning
use App::Notitia::Util     qw( build_tree iterator localise_tree mtime
                               register_action_paths uri_for_action );
use Class::Usul::Constants qw( NUL TRUE );
use Class::Usul::Functions qw( first_char throw );
use HTTP::Status           qw( HTTP_NOT_FOUND );
use Try::Tiny;
use Unexpected::Functions  qw( catch_class );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::PageLoading);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Editor);

has '+moniker' => default => 'docs';

register_action_paths
   'docs/dialog' => 'docs/dialog',
   'docs/index'  => 'docs',
   'docs/page'   => 'docs',
   'docs/search' => 'docs/search',
   'docs/upload' => 'assets';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav}->{id} = 'navigation';

   return $stash;
};

around 'load_page' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $page = $orig->( $self, $req, @args );

   $page->{location}   = 'documentation';
   $page->{template} //= [ 'contents', 'docs' ];

   return $page;
};

# Private package variables
my $_docs_tree_cache = { _mtime => 0, };
my $_docs_url_cache  = {};

# Private methods
my $_find_first_url = sub {
   my ($self, $tree) = @_; my $iter = iterator $tree;

   while (defined (my $node = $iter->())) {
      $node->{type} ne 'folder' and $node->{id} ne 'index'
         and return $node->{url};
   }

   my $error = 'Config Error: Unable to find the first page in the /docs '
             . 'folder. Double check you have at least one file in the root '
             . 'of the /docs folder. Also make sure you do not have any empty '
             . 'folders';

   $self->log->error( $error );
   return '/';
};

my $_docs_url = sub {
   my ($self, $locale) = @_;

   my $tree  = $self->localised_tree( $locale )
      or throw 'Locale [_1] has no document tree', [ $locale ],
         rv => HTTP_NOT_FOUND;
   my $tuple = $_docs_url_cache->{ $locale };
   my $mtime = mtime $tree;

   (not $tuple or $mtime > $tuple->[ 0 ]) and $_docs_url_cache->{ $locale }
      = $tuple = [ $mtime, $self->$_find_first_url( $tree ) ];

   return $tuple->[ 1 ];
};

# Public methods
sub base_uri {
   return uri_for_action( $_[ 1 ], 'docs/page', $_[ 2 ] );
}

sub create_file_action : Role(administrator) {
   return $_[ 0 ]->create_file( $_[ 1 ] );
}

sub delete_file_action : Role(administrator) {
   my ($self, $req) = @_; my $res = $self->delete_file( $req );

   $res->{redirect}->{location} = $self->docs_url( $req );

   return $res;
}

sub docs_url {
   return uri_for_action
      (   $_[ 1 ], $_[ 0 ]->moniker.'/page',
        [ $_[ 0 ]->$_docs_url( $_[ 2 ] // $_[ 1 ]->locale ) ] );
}

sub dialog : Role(any) {
   return $_[ 0 ]->get_dialog( $_[ 1 ] );
}

sub index : Role(anon) {
   my ($self, $req) = @_; my $location = $_[ 0 ]->docs_url( $_[ 1 ] );

   my $mid = $req->query_params->( 'mid', { optional => TRUE } );

   $mid and $location->query_form( mid => $mid );
   $location->query_form( navigation_reset => TRUE );

   return { redirect => { location => $location } };
}

sub locales {
   return grep { first_char $_ ne '_' } keys %{ $_[ 0 ]->tree_root };
}

sub localised_tree {
   return localise_tree $_[ 0 ]->tree_root, $_[ 1 ];
}

sub make_draft {
   my ($self, @pathname) = @_; return $self->config->drafts, @pathname;
}

sub nav_label {
   return sub { $_[ 0 ]->{title} };
}

sub page : Role(anon) {
   my ($self, $req) = @_;

   my $reset = $req->query_params->( 'navigation_reset', { optional => TRUE } );
   my $stash = $self->get_stash( $req );

   $reset and push @{ $stash->{page}->{literal_js} },
      "   behaviour.config[ 'sidebars' ] = { 'navigation_reset': true };";

   return $stash;
}

sub rename_file_action : Role(administrator) {
   return $_[ 0 ]->rename_file( $_[ 1 ] );
}

sub rename_file_path_fix {
   return $_[ 1 ];
}

sub save_file_action : Role(administrator) {
   return $_[ 0 ]->save_file( $_[ 1 ] );
}

sub search : Role(any) {
   return $_[ 0 ]->search_files( $_[ 1 ] );
}

sub tree_root {
   my $self = shift; my $conf = $self->config; my $filesys = $conf->docs_mtime;

   my $mtime = $filesys->exists ? $filesys->stat->{mtime} // 0 : 0;

   if ($mtime == 0 or $mtime > $_docs_tree_cache->{_mtime}) {
      my $no_index = join '|', @{ $conf->no_index };
      my $filter   = sub { not m{ (?: $no_index ) }mx };
      my $dir      = $conf->docs_root->clone->filter( $filter );

      $_docs_tree_cache = build_tree( $self->type_map, $dir );
      $filesys->touch( $_docs_tree_cache->{_mtime} );
   }

   return $_docs_tree_cache;
}

sub upload : Role(administrator) {
   my ($self, $req) = @_; my $res = $self->upload_file( $req );

   $res->{redirect}->{location} = $self->docs_url( $req );

   return $res;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Documentation - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Documentation;
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
