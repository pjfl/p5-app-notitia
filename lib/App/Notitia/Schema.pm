package App::Notitia::Schema;

use namespace::autoclean;

use App::Notitia; our $VERSION = $App::Notitia::VERSION;

use App::Notitia::Constants qw( AS_PASSWORD EXCEPTION_CLASS FALSE
                                NUL OK SLOT_TYPE_ENUM TRUE );
use App::Notitia::Util      qw( encrypted_attr new_request now_dt );
use Archive::Tar::Constant  qw( COMPRESS_GZIP );
use Class::Usul::Functions  qw( ensure_class_loaded io throw );
use Class::Usul::Types      qw( HashRef NonEmptySimpleStr Object );
use Format::Human::Bytes;
use Unexpected::Functions   qw( PathNotFound Unspecified );
use Web::Components::Util   qw( load_components );
use Moo;

extends q(Class::Usul::Schema);
with    q(App::Notitia::Role::Schema);

# Attribute constructors
my $_build_admin_password = sub {
   my $self = shift; my $prompt = '+Database administrator password';

   return encrypted_attr $self->config, $self->config->ctlfile,
             'admin_password', sub { $self->get_line( $prompt, AS_PASSWORD ) };
};

# Public attributes (override defaults in base class)
has 'admin_password'  => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => $_build_admin_password;

has '+config_class'   => default => 'App::Notitia::Config';

has '+database'       => default => sub { $_[ 0 ]->schema_database };

has '+preversion'     => is => 'rwp';

has '+rdbms'          => default => sub { $_[ 0 ]->config->rdbms };

has '+schema_classes' => default => sub { $_[ 0 ]->config->schema_classes };

has '+schema_version' => default => sub { App::Notitia->schema_version.NUL };

has 'components' => is => 'lazy', isa => HashRef[Object], builder => sub {
   return load_components 'Model', application => $_[ 0 ];
};

with q(App::Notitia::Role::EventStream);

# Construction
around 'deploy_file' => sub {
   my ($orig, $self, @args) = @_;

   $self->config->appclass->env_var( 'bulk_insert', TRUE );

   return $orig->( $self, @args );
};

# Private methods
my $_ddl_paths = sub {
   my $self = shift;

   return $self->ddl_paths
      ( $self->schema, $self->schema_version, $self->config->sharedir );
};

my $_needs_upgrade = sub {
   my $self = shift;

   $self->preversion and $self->_set_unlink( TRUE ) and return TRUE;

   my $db_version = $self->schema->get_db_version; $db_version
      and $db_version ne $self->schema_version
      and $self->_set_preversion( $db_version )
      and return TRUE;

   return FALSE;
};

my $_new_request = sub {
   my ($self, $scheme, $hostport) = @_;

   return new_request $self->config, $self->locale, $scheme, $hostport;
};

my $_add_backup_files = sub {
   my ($self, $arc) = @_; my $conf = $self->config;

   for my $cfgfile (map { io $_ } @{ $conf->cfgfiles }) {
      $arc->add_files( $cfgfile->abs2rel( $conf->appldir ) );
   }

   for my $doc ($conf->docs_root->clone->deep->all_files) {
      $arc->add_files( $doc->abs2rel( $conf->appldir ) );
   }

   my $localedir = $conf->localedir->clone->deep
                        ->filter( sub { m{ _local\.po \z }mx } );

   for my $pofile ($localedir->all_files) {
      $arc->add_files( $pofile->abs2rel( $conf->appldir ) );
   }

   for my $ddlfile ($self->$_ddl_paths) {
      $arc->add_files( $ddlfile->abs2rel( $conf->appldir) );
   }

   return;
};

# Public methods
sub backup_data : method {
   my $self = shift;
   my $now  = now_dt;
   my $conf = $self->config;
   my $date = $now->ymd( NUL ).'-'.$now->hms( NUL );
   my $file = $self->database."-${date}.sql";
   my $path = $conf->tempdir->catfile( $file );
   my $bdir = $conf->vardir->catdir( 'backups' );
   my $tarb = $conf->title."-${date}.tgz";
   my $out  = $bdir->catfile( $tarb )->assert_filepath;

   if (lc $self->driver eq 'mysql') {
      $self->run_cmd
         ( [ 'mysqldump', '--opt', '--host', $self->host,
             '--password='.$self->admin_password, '--result-file',
             $path->pathname, '--user', $self->db_admin_ids->{mysql},
             '--databases', $self->database ] );
   }

   chdir $conf->appldir; ensure_class_loaded 'Archive::Tar';

   my $arc = Archive::Tar->new; $self->$_add_backup_files( $arc );

   $path->exists and $arc->add_files( $path->abs2rel( $conf->appldir ) );
   $self->info( 'Generating backup [_1]', { args => [ $tarb ] } );
   $arc->write( $out->pathname, COMPRESS_GZIP ); $path->unlink;
   $file = $out->basename;

   my $size = Format::Human::Bytes->new()->base2( $out->stat->{size} );
   my $message = "action:backup-data relpath:${file} size:${size}";

   $self->send_event( $self->$_new_request, $message );

   return OK;
}

sub create_ddl : method {
   my $self = shift; $self->db_attr->{ignore_version} = TRUE;

   return $self->SUPER::create_ddl;
}

sub dump_connect_attr : method {
   my $self = shift; $self->dumper( $self->schema_connect_attr ); return OK;
}

sub deploy_and_populate : method {
   my $self    = shift; $self->db_attr->{ignore_version} = TRUE;
   my $rv      = $self->SUPER::deploy_and_populate;
   my $type_rs = $self->schema->resultset( 'Type' );
   my $sc_rs   = $self->schema->resultset( 'SlotCriteria' );

   for my $slot_type (@{ SLOT_TYPE_ENUM() }) {
      for my $cert_name (@{ $self->config->slot_certs->{ $slot_type } }) {
         my $cert = $type_rs->find_certification_by( $cert_name );

         $sc_rs->create( { slot_type             => $slot_type,
                           certification_type_id => $cert->id } );
      }
   }

   return $rv;
}

sub restore_data : method {
   my $self = shift; my $conf = $self->config;

   my $path = $self->next_argv or throw Unspecified, [ 'file name' ];

   $path = io $path; $path->exists or throw PathNotFound, [ $path ];

   chdir $conf->appldir; ensure_class_loaded 'Archive::Tar';

   my $arc = Archive::Tar->new; $arc->read( $path->pathname ); $arc->extract();

   my (undef, $date) = split m{ - }mx, $path->basename( '.tgz' ), 2;
   my $bdir = $conf->vardir->catdir( 'backups' );
   my $sql  = $conf->tempdir->catfile( $self->database."-${date}.sql" );

   if ($sql->exists and lc $self->driver eq 'mysql') {
      $self->run_cmd
         ( [ 'mysql', '--host', $self->host,
             '--password='.$self->admin_password, '--user',
             $self->db_admin_ids->{mysql}, $self->database ],
           { in => $sql } );
      $sql->unlink;
   }

   return OK;
}

sub upgrade_schema : method {
   my $self = shift; $self->db_attr->{ignore_version} = TRUE;

   $self->$_needs_upgrade
      or ($self->info( 'No schema upgrade required' ) and return OK);

   my $schema = $self->schema; $self->create_ddl;

   $schema->storage->ensure_connected;
   $schema->upgrade_directory( $self->config->sharedir );
   $schema->upgrade;
   return OK;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head2 C<backup_data> - Creates a backup of the database and documents

=head2 C<create_ddl> - Dump the database schema definition

Creates the DDL for multiple RDBMs

=head2 C<dump_connect_attr> - Displays database connection information

=head2 C<deploy_and_populate> - Create tables and populates them with initial data

=head2 C<restore_data> - Restore a backup of the database and documents

=head2 C<upgrade_schema> - Upgrade the database schema

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
