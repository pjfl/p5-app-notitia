package App::Notitia::Model::Posts;

use App::Notitia::Attributes;  # Will do cleaning
use App::Notitia::Util     qw( build_tree iterator localise_tree mtime
                               register_action_paths uri_for_action );
use Class::Usul::Constants qw( SPC TRUE );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::PageLoading);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Editor);
with    q(App::Notitia::Role::RSS);

has '+moniker' => default => 'posts';

register_action_paths
   'posts/dialog' => 'posts/dialog', 'posts/page' => 'posts',
   'posts/rss'    => 'posts/rss';

# Construction
around 'initialise_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args ); my $links = $stash->{links};

   $links->{rss_uri}
      = uri_for_action( $req, 'posts/rss', { extension => '.xml' } );

   return $stash;
};

around 'load_page' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $page  = $orig->( $self, $req, @args );
   my @ids   = @{ $req->uri_params->() // [] };
   my $type  = $page->{type} // 'folder';
   my $plate = $type eq 'folder' ? 'posts-index' : 'docs';

   $ids[ 0 ] and $ids[ 0 ] eq 'index' and @ids = ();
   $page->{wanted_depth}   = () = @ids;
   $page->{wanted      }   = join '/', $self->config->posts, @ids;
   $page->{template    } //= [ 'contents', $plate ];
   $page->{location    }   = 'posts';

   return $page;
};

# Private package variables
my $_posts_tree_cache = { _mtime => 0, };

# Private methods
my $_chain_nodes = sub {
   my ($self, $tree) = @_; my $iter = iterator $tree; my $prev;

   while (defined (my $node = $iter->())) {
      ($node->{type} eq 'folder' or $node->{id} eq 'index') and next;
      $prev and $prev->{next} = $node; $node->{prev} = $prev; $prev = $node;
   }

   return;
};

# Public methods
sub base_uri {
   return uri_for_action( $_[ 1 ], 'posts/page', $_[ 2 ] );
}

sub cancel_edit_action : Role(anon) {
   return $_[ 0 ]->page( $_[ 1 ], { cancel_edit => TRUE } );
}

sub create_file_action : Role(editor) {
   return $_[ 0 ]->create_file( $_[ 1 ] );
}

sub delete_file_action : Role(editor) {
   my ($self, $req) = @_; my $res = $self->delete_file( $req );

   $res->{redirect}->{location} = uri_for_action( $req, 'posts/page' );

   return $res;
}

sub dialog : Role(any) {
   return $_[ 0 ]->get_dialog( $_[ 1 ] );
}

sub localised_posts_dir {
   my ($self, $locale, $opts) = @_; my $conf = $self->config; $opts //= {};

   return $conf->docs_root->catdir( $locale, $conf->posts, $opts );
}

sub localised_tree {
   return localise_tree $_[ 0 ]->tree_root, $_[ 1 ];
}

sub make_draft {
   my ($self, @pathname) = @_; my $conf = $self->config; shift @pathname;

   return $conf->posts, $conf->drafts, @pathname;
}

sub nav_label {
   return sub { $_[ 0 ]->{prefix}.SPC.$_[ 0 ]->{title} };
}

sub page : Role(anon) {
   my $self = shift; return $self->get_stash( @_ );
}

sub rename_file_action : Role(editor) {
   return $_[ 0 ]->rename_file( $_[ 1 ] );
}

sub rename_file_path_fix {
   my ($self, $path) = @_; shift @{ $path }; return $path;
}

sub rss_feed : Role(anon) {
   return $_[ 0 ]->get_rss_feed( $_[ 1 ] );
}

sub save_file_action : Role(editor) {
   return $_[ 0 ]->save_file( $_[ 1 ] );
}

sub tree_root {
   my $self = shift; my $conf = $self->config; my $filesys = $conf->docs_mtime;

   my $mtime = $filesys->exists ? $filesys->stat->{mtime} // 0 : 0;

   if ($mtime == 0 or $mtime > $_posts_tree_cache->{_mtime}) {
      my $postd     = $conf->posts;
      my $no_index  = join '|', grep { not m{ $postd }mx } @{ $conf->no_index };
      my $max_mtime = $_posts_tree_cache->{_mtime};

      for my $locale (@{ $conf->locales }) {
         my $lcache = $_posts_tree_cache->{ $locale } //= {};
         my $dir    = $self->localised_posts_dir( $locale, { reverse => TRUE } )
                           ->filter( sub { not m{ (?: $no_index ) }mx } );

         $dir->exists or next;
         $lcache->{tree} = build_tree( $self->type_map, $dir, 2 );
         $lcache->{type} = 'folder';
         $self->$_chain_nodes( $lcache );

         my $mtime = mtime $lcache; $mtime > $max_mtime and $max_mtime = $mtime;
      }

      $filesys->touch( $_posts_tree_cache->{_mtime} = $max_mtime );
   }

   return $_posts_tree_cache;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Posts - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Posts;
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
