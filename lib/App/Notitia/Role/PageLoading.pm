package App::Notitia::Role::PageLoading;

use namespace::autoclean;

use App::Notitia::DOM      qw( p_js );
use App::Notitia::Util     qw( build_navigation clone is_access_authorised
                               js_togglers_config loc local_dt mtime to_dt );
use Class::Usul::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use Class::Usul::Functions qw( is_arrayref is_member throw );
use Class::Usul::Time      qw( time2str );
use Class::Usul::Types     qw( HashRef );
use English                qw( -no_match_vars );
use Unexpected::Functions  qw( AuthenticationRequired );
use Moo::Role;

requires qw( components config depth_offset get_stash load_page
             localised_tree max_navigation nav_label navigation_links );

has 'type_map' => is => 'ro', isa => HashRef, builder => sub { {} };

# Private functions
my $_add_edit_js = sub {
   my $page = shift;
   my $t1   = "<i class='edit-panel-icon true'></i>";
   my $t2   = "<i class='edit-panel-icon false'></i>";

   p_js $page, js_togglers_config 'toggle-edit', 'click',
      'toggleSwapText', [ 'toggle-edit', 'edit-panel', $t1, $t2 ];

   return;
};

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $views = $attr->{views} or return $attr;

   exists $views->{html} and $attr->{type_map}
        = $views->{html}->can( 'type_map' ) ? $views->{html}->type_map : {};

   return $attr;
};

around 'load_page' => sub {
   my ($orig, $self, $req, @args) = @_; my $page = $args[ 0 ]; my %seen = ();

   $page and not $page->{cancel_edit}
         and return $orig->( $self, $req, @args );

   my $cancel_edit = $page->{cancel_edit} ? TRUE : FALSE;
   my $who         = $req->session->user_label
                  || loc( $req, 'Person' ).SPC.$req->username;

   for my $locale ($req->locale, @{ $req->locales }, $self->config->locale) {
      $seen{ $locale } and next; $seen{ $locale } = TRUE;

      my $node = $self->find_node( $req, $locale, $req->uri_params->() )
         or next;

      is_access_authorised( $req, $node )
         or throw '[_1] authentication required',
            args => [ $who ], class => AuthenticationRequired->();

      my $page = $self->initialise_page( $req, $node, $locale );

      $page->{cancel_edit} = $cancel_edit;
      $page = $orig->( $self, $req, $page );
      $req->authenticated and $_add_edit_js->( $page );

      return $page;
   }

   throw 'Page [_1] not found', [ $req->path ];
};

# Public methods
sub docs_mtime_cache {
   my ($self, $req, $v) = @_;

   defined $v or return $req->state_cache( 'docs_mtime' ) // 0;

   $v =~ m{ \A [0-9]+ \z }mx
      or throw 'Docs cache mtime [_1] must be an integer', [ $v ];

   return $req->state_cache( 'docs_mtime', $v );
}

sub find_node {
   my ($self, $req, $locale, $ids) = @_;

   my $node = $self->localised_tree( $req, $locale ) or return FALSE;

   $ids //= []; $ids->[ 0 ] //= 'index';

   for my $node_id (@{ $ids }) {
      $node->{type} and $node->{type} eq 'folder' and $node = $node->{tree};
      exists  $node->{ $node_id } or return FALSE;
      $node = $node->{ $node_id };
   }

   return $node;
}

sub find_node_by_path {
   my ($self, $req, $path) = @_;

   my @path = split m{ / }mx, $path; my %seen = ();

   for my $locale ($req->locale, @{ $req->locales }, $self->config->locale) {
      $seen{ $locale } and next; $seen{ $locale } = TRUE;

      my $node = $self->find_node( $req, $locale, \@path ) or next;

      return $node;
   }

   return;
}

sub initialise_page {
   my ($self, $req, $node, $locale) = @_; my $page = clone $node;

   $page->{content} = delete $page->{path}; $page->{locale} = $locale;

   return $page;
}

sub invalidate_docs_cache {
   my ($self, $req, $mtime) = @_;

   if ($mtime) {
      $self->docs_mtime_cache( $req, $mtime );
      $mtime = local_dt to_dt time2str undef, $mtime;
      $self->log->info( "Invalidate docs cache ${mtime} ${PID}" );
   }
   else {
      $self->docs_mtime_cache( $req, 0 );
      $self->log->info( 'Invalidate docs cache 0 ${PID}' );
   }

   return;
}

sub navigation {
   my ($self, $req) = @_;

   my $conf = $self->config;
   my $locale = $conf->locale; # Always index config default language
   my $node = $self->localised_tree( $req, $locale )
      or throw 'Default locale [_1] has no document tree', [ $locale ];

   return build_navigation $req, {
      config => $conf,
      depth_offset => $self->depth_offset,
      label => $self->nav_label,
      limit => $self->max_navigation,
      node => $node,
      path => $self->moniker.'/page',
   };
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
