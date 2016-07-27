package App::Notitia::Role::Editor;

use namespace::autoclean;

use App::Notitia::Form     qw( blank_form f_tag p_button p_checkbox p_file
                               p_hidden p_list p_radio p_span p_text
                               p_textfield );
use App::Notitia::Util     qw( dialog_anchor locm make_id_from
                               make_name_from mtime set_element_focus
                               stash_functions to_msg uri_for_action );
use Class::Usul::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::Functions qw( io is_member throw trim untaint_path );
use Class::Usul::IPC;
use Class::Usul::Time      qw( time2str );
use Class::Usul::Types     qw( ProcCommer );
use List::Util             qw( first );
use Scalar::Util           qw( blessed );
use Unexpected::Functions  qw( Unspecified );
use Moo::Role;

requires qw( application components config find_node initialise_stash
             invalidate_docs_cache load_page log make_draft );

with q(Web::Components::Role::TT);

# Private attributes
has '_ipc' => is => 'lazy', isa => ProcCommer, handles => [ 'run_cmd' ],
   builder => sub { Class::Usul::IPC->new( builder => $_[ 0 ]->application ) };

# Private class attributes
my @extensions = qw( .csv .doc .docx .gif .jpeg .jpg .png .xls .xlsx );

# Private methods
my $_add_dialog_js = sub {
   my ($self, $req, $page, $name, $opts) = @_;

   my $action = $self->moniker.'/dialog';
   my $href   = uri_for_action( $req, $action, [], { name => $name } );

   push @{ $page->{literal_js} }, dialog_anchor
      "${name}-file", $href, { name => "${name}-file", %{ $opts } };
   return;
};

my $_add_editing_js = sub {
   my ($self, $req, $page) = @_;

  (defined $page->{content} and blessed $page->{content}) or return;

   my $map = { create => 'Create File',      rename => 'Rename File',
               search => 'Search Documents', upload => 'Upload File', };

   for my $name (keys %{ $map }) {
      my $opts = { title => locm( $req, $map->{ $name } ), useIcon => \1 };

      $name eq 'rename'and $opts->{value} = $page->{url};
      $self->$_add_dialog_js( $req, $page, $name, $opts);
   }

   $page->{form_name} = 'editing';
   return;
};

# Construction
around 'initialise_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash  = $orig->( $self, $req, @args ); my $links = $stash->{links};

   $links->{root_uri} = $self->base_uri( $req );
   $links->{edit_uri} = $req->uri_for( $req->path, [], edit => TRUE );

   return $stash;
};

around 'load_page' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $page    = $orig->( $self, $req, @args );
   my $editing = $req->query_params->( 'edit', { optional => TRUE } )
               ? TRUE : FALSE;

   $page->{editing} =  $page->{cancel_edit} ? FALSE : $editing;
   $page->{editing} or $self->$_add_editing_js( $req, $page );

   $req->authenticated and $page->{user}
      = $self->components->{person}->find_by_shortcode( $req->username );

   my $editors = qr{ \A (?: editor|event_manager|person_manager ) \z }mx;

   $page->{is_editor} = ($req->authenticated && first { $_ =~ $editors }
                        @{ $req->session->roles }) ? TRUE : FALSE;

   return $page;
};

# Private functions
my $_append_suffix = sub {
   my $path = untaint_path $_[ 0 ];

   $path !~ m{ \. [m][k]?[d][n]? \z }mx and $path .= '.md';

   return $path;
};

my $_copy_element_value = sub {
   return [ "\$( 'upload-btn' ).addEvent( 'change', function( ev ) {",
            "   ev.stop(); \$( 'upload-path' ).value = this.value } )", ];
};

my $_prepare_path = sub {
   my $path = shift; $path =~ s{ [\\] }{/}gmx;

   return (map { s{ [ ] }{_}gmx; $_ }
           map { trim $_            } split m{ / }mx, $path);
};

my $_prune = sub {
   my $path = shift; my $dir = $path->parent;

   while ($dir->exists and $dir->is_empty) { $dir->rmdir; $dir = $dir->parent }

   return $dir;
};

my $_result_line = sub {
   return $_[ 0 ].'\. ['.$_[ 1 ]->[ 0 ].']('.$_[ 1 ]->[ 1 ].")\n\n> "
         .$_[ 1 ]->[ 2 ];
};

my $_fettle_path = sub {
   my ($self, $locale, @pathname) = @_; my $opts = pop @pathname;

   $opts->{draft} and @pathname = $self->make_draft( @pathname );

   not $opts->{draft} and defined $opts->{prefix}
      and unshift @pathname, $opts->{prefix};

   return $self->config->docs_root->catfile( $locale, @pathname )->utf8;
};

# Private methods
my $_new_node = sub {
   my ($self, $locale, $pathname, $opts) = @_; my $conf = $self->config;

   my @pathname = $_prepare_path->( $_append_suffix->( $pathname ) );

   $opts->{draft} and @pathname = ($self->config->drafts, @pathname);

   my $path     = $self->$_fettle_path( $locale, @pathname, $opts );
   my @filepath = map { make_id_from( $_ )->[ 0 ] } @pathname;
   my $url      = join '/', @filepath;
   my $id       = pop @filepath;
   my $parent   = $self->find_node( $locale, \@filepath );

   $parent and $parent->{type} eq 'folder'
      and exists $parent->{tree}->{ $id }
      and $parent->{tree}->{ $id }->{path} eq $path
      and throw 'Path [_1] already exists', [ $path ];

   return { path => $path, url => $url, };
};

my $_prepare_search_results = sub {
   my ($self, $req, $langd, $results) = @_;

   my $actionp = $self->moniker.'/page';
   my @tuples  = map { [ split m{ : }mx, $_, 3 ] } split m{ \n }mx, $results;

   for my $tuple (@tuples) {
      my @pathname = $_prepare_path->( io( $tuple->[ 0 ] )->abs2rel( $langd ) );
      my @filepath = map { make_id_from( $_ )->[ 0 ] } @pathname;
      my $path     = join '/', @filepath;
      my $name     = make_name_from $path; $name =~ s{/}{ / }gmx;

      $tuple->[ 0 ] = $name;
      $tuple->[ 1 ] = uri_for_action $req, $actionp, [ $path ];
   }

   return @tuples;
};

my $_search_results = sub {
   my ($self, $req) = @_;

   my $count   = 1;
   my $scrub   = '[^ 0-9A-Z_a-z]';
   my $query   = $req->query_params->( 'query', { scrubber => $scrub } );
   my $langd   = $self->config->docs_root->catdir( $req->locale );
   my $resp    = $self->run_cmd
                 ( [ 'ack', '-i', $query, "${langd}" ], { expected_rv => 1, } );
   my $results = $resp->rv == 1
               ? $langd->catfile( locm $req, 'Nothing found' ).'::'
               : $resp->stdout;
   my @tuples  = $self->$_prepare_search_results( $req, $langd, $results );
   my $content = join "\n\n", map { $_result_line->( $count++, $_ ) } @tuples;
   my $leader  = locm( $req, 'You searched for "[_1]"', $query )."\n\n";
   my $name    = locm( $req, 'Search Results' );

   return { content => $leader.$content,
            format  => 'markdown',
            mtime   => time,
            name    => $name,
            title   => ucfirst $name, };
};

# Public methods
sub create_file {
   my ($self, $req, $opts) = @_; $opts //= {};

   my $conf     = $self->config;
   my $params   = $req->body_params;
   my $pathname = $params->( 'pathname' );

   $opts->{draft} = $params->( 'draft', { optional => TRUE } ) || FALSE;

   my $new_node = $self->$_new_node( $req->locale, $pathname, $opts );
   my $created  = time2str '%Y-%m-%d %H:%M:%S %z', time, 'GMT';
   my $stash    = { page => { author  => $req->username,
                              created => $created,
                              layout  => 'blank-page', }, };

   stash_functions $self, $req, $stash;

   my $content  = $self->render_template( $stash );
   my $path     = $new_node->{path};

   $path->assert_filepath->println( $content )->close;
   $self->invalidate_docs_cache( $path->stat->{mtime} );

   my $rel_path = $path->abs2rel( $conf->docs_root );
   my $message  = [ to_msg 'File [_1] created by [_2]',
                    $rel_path, $req->session->user_label ];
   my $location = $self->base_uri( $req, [ $new_node->{url} ] );

   return { redirect => { location => $location, message => $message } };
}

sub delete_file {
   my ($self, $req) = @_;

   my $node = $self->find_node( $req->locale, $req->uri_params->() )
      or throw 'Cannot find document tree node to delete';
   my $path = $node->{path};

   $path->exists and $path->unlink; $_prune->( $path );
   $self->invalidate_docs_cache;

   my $location = $self->base_uri( $req );
   my $rel_path = $path->abs2rel( $self->config->docs_root );
   my $message  = [ to_msg 'File [_1] deleted by [_2]',
                    $rel_path, $req->session->user_label ];

   return { redirect => { location => $location, message => $message } };
}

sub get_dialog {
   my ($self, $req) = @_;

   my $params = $req->query_params;
   my $name   = $params->( 'name' );
   my $val    = $params->( 'val', { optional => TRUE } );
   my $stash  = $self->dialog_stash( $req );
   my $links  = $stash->{links};
   my $href   = $name eq 'create' ? $links->{root_uri}
              : $name eq 'rename' ? $self->base_uri( $req, [ $val ] )
              : $name eq 'search' ? uri_for_action $req, 'docs/search'
              : $name eq 'upload' ? uri_for_action $req, 'docs/upload'
                                  : NUL;
   my $form   = $stash->{page}->{forms}->[ 0 ]
              = blank_form "${name}-file", $href;
   my $page   = $stash->{page};
   my $opts   = { class => 'button right-last' };

   if ($name eq 'create') {
      p_textfield $form, 'pathname', NUL, { class => 'pathname', label => NUL };
      p_radio     $form, 'draft', [ [ 'Draft', TRUE ] ], { label => NUL };
      p_button    $form, 'Create', 'create_file', $opts;
      $page->{literal_js} = set_element_focus "${name}-file", 'pathname';
   }
   elsif ($name eq 'rename') {
      p_hidden    $form, 'old_path', $val;
      p_textfield $form, 'pathname', NUL, { class => 'pathname', label => NUL };
      p_text      $form, NUL, $val, { class => 'info-field' };
      p_button    $form, 'Rename', 'rename_file', $opts;
      $page->{literal_js} = set_element_focus "${name}-file", 'pathname';
   }
   elsif ($name eq 'search') {
      $form->{method} = 'get';
      p_textfield $form, 'query', $stash->{prefs}->{query}, { label => NUL };
      p_button    $form, 'Search', NUL, $opts;
      $page->{literal_js} = set_element_focus "${name}-file", 'query';
   }
   elsif ($name eq 'upload') {
      $page->{offer_public} = TRUE; $self->upload_dialog( $req, $page );
   }

   return $stash;
}

sub rename_file {
   my ($self, $req) = @_;

   my $conf     = $self->config;
   my $params   = $req->body_params;
   my $old_path = $self->rename_file_path_fix
      ( [ split m{ / }mx, $params->( 'old_path' ) ] );
   my $node     = $self->find_node( $req->locale, $old_path )
      or throw 'Cannot find document tree node to rename';
   my $new_node = $self->$_new_node( $req->locale, $params->( 'pathname' ) );

   $new_node->{path}->assert_filepath;
   $node->{path}->close->move( $new_node->{path} ); $_prune->( $node->{path} );
   $self->invalidate_docs_cache;

   my $rel_path = $node->{path}->abs2rel( $conf->docs_root );
   my $message  = [ to_msg 'File [_1] renamed by [_2]',
                    $rel_path, $req->session->user_label ];
   my $location = $self->base_uri( $req, [ $new_node->{url} ] );

   return { redirect => { location => $location, message => $message } };
}

sub save_file {
   my ($self, $req) = @_;

   my $node     =  $self->find_node( $req->locale, $req->uri_params->() )
      or throw 'Cannot find document tree node to update';
   my $content  =  $req->body_params->( 'content', { raw => TRUE } );
      $content  =~ s{ \r\n }{\n}gmx; $content =~ s{ \s+ \z }{}mx;
   my $path     =  $node->{path}; $path->println( $content ); $path->close;
   my $rel_path =  $path->abs2rel( $self->config->docs_root );
   my $message  =  [ to_msg 'File [_1] updated by [_2]',
                     $rel_path, $req->session->user_label ];
   my $location =  $self->base_uri( $req, [ $node->{url} ] );

   $self->invalidate_docs_cache( $path->stat->{mtime} );

   return { redirect => { location => $location, message => $message } };
}

sub search_files {
   my ($self, $req) = @_;

   return $self->get_stash( $req, $self->$_search_results( $req ) );
}

sub upload_dialog {
   my ($self, $req, $page) = @_;

   my $form    = $page->{forms}->[ 0 ];

   p_textfield $form, 'upload-path', NUL, {
      class => 'pathname', disabled => TRUE,
      label => NUL, placeholder => 'Choose File' };

   $page->{offer_public} and p_checkbox $form, 'public_access', TRUE, {
      label_class => 'align-right clear' };

   my $list = p_list $form, f_tag( 'br' ), [], { class => 'upload-file button'};

   p_span $list, locm $req, 'Browse';
   p_file $list, 'file', NUL, { class => 'upload', id => 'upload-btn' };
   p_button $form, 'Upload', 'upload_file', { class => 'button right-last' };

   $page->{literal_js} = $_copy_element_value->();
   $form->{enctype} = 'multipart/form-data';
   return;
}

sub upload_file {
   my ($self, $req) = @_; my $conf = $self->config;

   my $public = $req->body_params->( 'public_access', { optional => TRUE } )
             || FALSE;
   my $name   = $req->query_params->( 'name', { optional => TRUE } );
   my $type   = $req->query_params->( 'type', { optional => TRUE } );

   my $upload; ($req->has_upload and $upload = $req->upload)
      or throw Unspecified, [ 'upload object' ];

   $upload->is_upload or throw $upload->reason;

   $upload->size > $conf->max_asset_size and
      throw 'File [_1] size [_2] too big', [ $upload->filename, $upload->size ];

   my $dir    = $public ? $conf->assetdir->catdir( 'public' )
              : $type   ? $conf->assetdir->catdir( $type )
              :           $conf->assetdir;
   my ($extn) = $upload->filename =~ m{ ( \. .+) \z }mx;

   is_member $extn, @extensions or throw 'File type [_1] unknown', [ $extn ];

   my $file   = $name ? "${name}${extn}" : $upload->filename;
   my $dest   = $dir->catfile( $file )->assert_filepath;

   io( $upload->path )->copy( $dest );

   my $rel_path = $dest->abs2rel( $conf->assetdir );
   my $message  = [ to_msg 'File [_1] uploaded by [_2]',
                    $rel_path, $req->session->user_label ];
   my $location = $self->base_uri( $req );

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::Editor - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::Editor;
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
