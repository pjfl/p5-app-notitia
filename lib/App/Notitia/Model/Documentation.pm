package App::Notitia::Model::Documentation;

use App::Notitia::Attributes;  # Will do cleaning
use App::Notitia::Util     qw( build_tree iterator localise_tree
                               mtime register_action_paths
                               set_last_modified_header );
use Class::Usul::Constants qw( NUL TRUE );
use Class::Usul::Functions qw( first_char throw );
use Class::Usul::Types     qw( NonZeroPositiveInt PositiveInt );
use English                qw( -no_match_vars );
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);

has '+moniker' => default => 'docs';

has 'depth_offset' => is => 'ro', isa => PositiveInt, default => 2;

has 'max_navigation' => is => 'ro', isa => NonZeroPositiveInt, default => 1000;

with q(App::Notitia::Role::PageConfiguration);
with q(App::Notitia::Role::Navigation);
with q(App::Notitia::Role::PageLoading);
with q(App::Notitia::Role::WebAuthorisation);
with q(App::Notitia::Role::Editor);

register_action_paths
   'docs/dialog' => 'docs/dialog',
   'docs/index'  => 'docs',
   'docs/page'   => 'docs',
   'docs/search' => 'docs/search',
   'docs/upload' => 'asset';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{navigation} = $self->navigation_links( $req, $stash->{page} );
   $stash->{navigation}->{menu}->{list} = $self->navigation( $req );
   $stash->{navigation}->{menu}->{class} = 'dropmenu';

   return $stash;
};

around 'load_page' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $page = $orig->( $self, $req, @args );
   my $skin = $req->session->skin || $self->config->skin;

   defined $page->{template}->[ 1 ]
        or $page->{template}->[ 1 ] = "${skin}/documentation";

   $page->{location} = 'documentation';
   return $page;
};

# Private package variables
my $_docs_cache = { _mtime => 0, };
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
   my ($self, $req, $locale) = @_;

   my $tree  = $self->localised_tree( $req, $locale )
      or throw 'Locale [_1] has no document tree', [ $locale ];
   my $tuple = $_docs_url_cache->{ $locale };
   my $mtime = mtime $tree;

   (not $tuple or $mtime > $tuple->[ 0 ]) and $_docs_url_cache->{ $locale }
      = $tuple = [ $mtime, $self->$_find_first_url( $tree ) ];

   return $tuple->[ 1 ];
};

# Public methods
sub base_uri {
   return $_[ 1 ]->uri_for_action( 'docs/page', $_[ 2 ] );
}

sub cancel_edit_action : Role(anon) {
   return $_[ 0 ]->page( $_[ 1 ], { cancel_edit => TRUE } );
}

sub create_file_action : Role(editor) {
   return $_[ 0 ]->create_file( $_[ 1 ] );
}

sub delete_file_action : Role(editor) {
   my ($self, $req) = @_; my $stash = $self->delete_file( $req );

   $stash->{redirect}->{location} = $self->docs_url( $req );

   return $stash;
}

sub docs_url {
   return $_[ 1 ]->uri_for_action
      (   $_[ 0 ]->moniker.'/page',
        [ $_[ 0 ]->$_docs_url( $_[ 1 ], $_[ 2 ] // $_[ 1 ]->locale ) ] );
}

sub dialog : Dialog Role(any) {
   return $_[ 0 ]->get_dialog( $_[ 1 ] );
}

sub index : Role(anon) {
   my ($self, $req) = @_;

   my $mid = $req->session->collect_message_id( $req );
   my $location = $self->docs_url( $req );
   my %query = $location->query_form;

   $mid and $location->query_form( %query, mid => $mid );

   return { redirect => { location => $location } };
}

sub localised_tree {
   return localise_tree $_[ 0 ]->tree_root( $_[ 1 ] ), $_[ 2 ];
}

sub nav_label {
   return sub { my ($req, $link) = @_; $link->{title} };
}

sub page : Role(anon) {
   my ($self, $req, $page) = @_;

   my $stash = $self->get_stash( $req, $page );

   set_last_modified_header $stash, $stash->{page}->{modified};

   return $stash;
}

sub qualify_path {
   my ($self, $locale, @pathname) = @_; my $opts = pop @pathname;

   $opts->{draft} and unshift @pathname, $self->config->drafts;

   return $self->config->docs_root->catfile( $locale, @pathname )->utf8;
}

sub rename_file_action : Role(editor) {
   return $_[ 0 ]->rename_file( $_[ 1 ] );
}

sub save_file_action : Role(editor) {
   return $_[ 0 ]->save_file( $_[ 1 ] );
}

sub search : Role(any) {
   return $_[ 0 ]->search_files( $_[ 1 ] );
}

sub tree_root {
   my ($self, $req) = @_; my $mtime = $self->docs_mtime_cache( $req );

   if ($mtime == 0 or $mtime > $_docs_cache->{_mtime}) {
      my $conf     = $self->config;
      my $no_index = join '|', @{ $conf->no_index };
      my $filter   = sub { not m{ (?: $no_index ) }mx };
      my $dir      = $conf->docs_root->clone->filter( $filter );

      $self->log->info( "Tree building ${dir} ${PID}" );
      $_docs_cache = build_tree( $self->type_map, $dir );

      if ($_docs_cache->{_mtime} > $mtime) {
         $self->docs_mtime_cache( $req, $_docs_cache->{_mtime} );
      }
      else { $_docs_cache->{_mtime} = $mtime }
   }

   return $_docs_cache;
}

sub upload : Role(editor) Role(event_manager) Role(person_manager) {
   return $_[ 0 ]->upload_file( $_[ 1 ] );
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
