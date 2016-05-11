package App::Notitia::Role::PageLoading;

use namespace::autoclean;

use App::Notitia::Util     qw( build_navigation clone mtime );
use Class::Usul::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::File;
use Class::Usul::Functions qw( is_arrayref is_member throw );
use Class::Usul::Types     qw( HashRef );
use Moo::Role;

requires qw( components config initialise_stash load_page localised_tree );

has 'type_map' => is => 'ro', isa => HashRef, builder => sub { {} };

# Private class attributes
my $_nav_cache = {};

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $views = $attr->{views} or return $attr;

   exists $views->{html} and $attr->{type_map}
        = $views->{html}->can( 'type_map' ) ? $views->{html}->type_map : {};

   return $attr;
};

around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav}->{list} = $self->navigation( $req, $stash );

   return $stash;
};

my $_is_user_authorised = sub {
   my ($self, $req, $node) = @_; my $nroles = $node->{role};

   $nroles = is_arrayref( $nroles ) ? $nroles : $nroles ? [ $nroles ] : [];

   is_member 'anon', $nroles and return TRUE;
   $req->authenticated or return FALSE;
   is_member 'any',  $nroles and return TRUE;

   my $person = $self->components->{person}->find_by_shortcode( $req->username);
   my $proles = $person->list_roles;

   is_member 'administrator', $proles and return TRUE;

   for my $role (@{ $nroles }) { is_member $role, $proles and return TRUE }

   return FALSE;
};

around 'load_page' => sub {
   my ($orig, $self, $req, @args) = @_; my $page = $args[ 0 ]; my %seen = ();

   $page and not $page->{cancel_edit}
         and return $orig->( $self, $req, @args );

   my $cancel_edit = $page->{cancel_edit} ? TRUE : FALSE;

   for my $locale ($req->locale, @{ $req->locales }, $self->config->locale) {
      $seen{ $locale } and next; $seen{ $locale } = TRUE;

      my $node = $self->find_node( $locale, $req->uri_params->() ) or next;

      $self->$_is_user_authorised( $req, $node )
         or throw 'Person [_1] permission denied', [ $req->username ];

      my $page = $self->initialise_page( $req, $node, $locale );

      $page->{cancel_edit} = $cancel_edit;

      return $orig->( $self, $req, $page );
   }

   throw 'Page [_1] not found', [ $req->path ];
};

# Private methods
my $_update_filesys = sub {
   my ($self, $text, $file, $mtime) = @_;

   if ($mtime) { $file->touch( $mtime ) }
   else { $file->exists and $file->unlink }

   $self->log->debug( $text );

   return;
};

# Public methods
sub find_node {
   my ($self, $locale, $ids) = @_;

   my $node = $self->localised_tree( $locale ) or return FALSE;

   $ids //= []; $ids->[ 0 ] //= 'index';

   for my $node_id (@{ $ids }) {
      $node->{type} and $node->{type} eq 'folder' and $node = $node->{tree};
      exists  $node->{ $node_id } or return FALSE;
      $node = $node->{ $node_id };
   }

   return $node;
}

sub initialise_page {
   my ($self, $req, $node, $locale) = @_; my $page = clone $node;

   $page->{content} = delete $page->{path}; $page->{locale} = $locale;

   return $page;
}

sub invalidate_docs_cache {
   my ($self, $mtime) = @_; $_nav_cache = {};

   my $filesys = $self->config->docs_mtime;

   $self->$_update_filesys( 'Document cache invalidated', $filesys, $mtime );

   return;
}

sub navigation {
   my ($self, $req, $stash) = @_;

   my $conf     = $self->config;
   my $locale   = $conf->locale; # Always index config default language
   my $node     = $self->localised_tree( $locale )
      or  throw 'Default locale [_1] has no document tree', [ $locale ];
   my $location = $stash->{page}->{location};
   my $key      = $req->authenticated ? "${location}_auth" : "${location}_anon";
   my $tuple    = $_nav_cache->{ $key };

   if (not $tuple or mtime $node > $tuple->{mtime}) {
      my $opts = { config => $conf, label => $self->nav_label,
                   node   => $node, path  => $self->moniker.'/page' };

      $tuple  =  $_nav_cache->{ $key } = {
         list => build_navigation( $req, $opts ), mtime => mtime( $node ), };
   }

   return $tuple->{list};
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::PageLoading - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::PageLoading;
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
