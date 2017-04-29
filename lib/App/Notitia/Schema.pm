package App::Notitia::Schema;

use namespace::autoclean;

use App::Notitia; our $VERSION = $App::Notitia::VERSION;

use App::Notitia::Constants qw( AS_PASSWORD EXCEPTION_CLASS FALSE
                                NUL OK SLOT_TYPE_ENUM TRUE );
use App::Notitia::Util      qw( encrypted_attr new_request now_dt );
use Archive::Tar::Constant  qw( COMPRESS_GZIP );
use Class::Usul::Functions  qw( ensure_class_loaded io throw );
use Class::Usul::Types      qw( HashRef LoadableClass
                                NonEmptySimpleStr Object );
use Format::Human::Bytes;
use Unexpected::Functions   qw( PathNotFound Unspecified );
use Web::Components::Util   qw( load_components );
use Moo;

extends q(Class::Usul::Schema);
with    q(App::Notitia::Role::Schema);
with    q(App::Notitia::Role::UserTable);

has 'components' => is => 'lazy', isa => HashRef[Object], builder => sub {
   return load_components 'Model', application => $_[ 0 ];
};

with q(App::Notitia::Role::EventStream);

# Attribute constructors
my $_build_admin_password = sub {
   my $self = shift; my $prompt = '+Database administrator password';

   return encrypted_attr $self->config, $self->config->ctlfile,
             'admin_password', sub { $self->get_line( $prompt, AS_PASSWORD ) };
};

# Public attributes (override defaults in base class)
has 'admin_password'  => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => $_build_admin_password;

has 'admin_user'      => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => sub { $_[ 0 ]->db_admin_ids->{ $_[ 0 ]->driver } };

has '+config_class'   => default => 'App::Notitia::Config';

has '+database'       => default => sub { $_[ 0 ]->schema_database };

has 'driver2producer' => is => 'ro', isa => HashRef, builder => sub { {
   mysql => 'MySQL', pg => 'PostgreSQL', sqlite => 'SQLite',
} };

has '+rdbms'          => default => sub { $_[ 0 ]->config->rdbms };

has '+schema_classes' => default => sub { $_[ 0 ]->config->schema_classes };

has '+schema_version' => default => sub { App::Notitia->schema_version.NUL };

has 'sqlt_class'      => is => 'lazy', isa => LoadableClass,
   builder            => sub { 'SQL::Translator' };

# Construction
around 'deploy_file' => sub {
   my ($orig, $self, @args) = @_;

   $self->config->appclass->env_var( 'bulk_insert', TRUE );

   return $orig->( $self, @args );
};

# Private functions
my $_create_table = sub {
   my ($sqlt, $args) = @_;

   my $ud_table   = ${ $args }->[ 1 ];
   my $sqlt_table = $sqlt->schema->add_table( name => $ud_table->name )
      or throw $sqlt->error;

   for my $column ($ud_table->columns->all) {
      $sqlt_table->add_field(
         data_type         => $column->data_type,
         default_value     => $column->default_value,
         is_auto_increment => $column->name eq 'id' ? TRUE : FALSE,
         is_nullable       => $column->nullable,
         name              => $column->name,
         size              => $column->size,
      ) or throw $sqlt_table->error;

      $column->name eq 'id' and $sqlt_table->primary_key( 'id' );
   }

   return TRUE;
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
   return new_request {
      config   => $_[ 0 ]->config,
      locale   => $_[ 0 ]->locale,
      scheme   => $_[ 1 ],
      hostport => $_[ 2 ], };
};

my $_table_connect_attr = sub {
   my $self = shift;

   return {
      database => 'usertable',
      password => $self->table_schema_connect_attr->[ 2 ],
      user     => $self->table_schema_connect_attr->[ 1 ], };
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

my $_backup_command = sub {
   my ($self, $path) = @_; my $cmd;

   if (lc $self->driver eq 'mysql') {
      $cmd = [ 'mysqldump', '--opt', '--host', $self->host,
               '--password='.$self->admin_password, '--result-file',
               $path->pathname, '--user', $self->admin_user,
               '--databases', $self->database ];
   }
   elsif (lc $self->driver eq 'pg') {
      $cmd = 'PGPASSWORD='.$self->admin_password.' pg_dumpall '
           . '--file='.$path.' -h '.$self->host.' -U '.$self->admin_user;
   }

   $cmd or throw 'No backup command for driver '.$self->driver;

   return $cmd;
};

my $_restore_command = sub {
   my ($self, $sql) = @_; my $cmd;

   my $user = $self->admin_user;

   if (lc $self->driver eq 'mysql') {
      $cmd  = 'mysql --host '.$self->host.' --password='.$self->admin_password
            . " --user ${user} ".$self->database." < ${sql}";
   }
   elsif (lc $self->driver eq 'pg') {
      $cmd  = 'PGPASSWORD='.$self->admin_password.' pg_restore '
            . '-C -d postgres -h '.$self->host." -U ${user} ${sql}";
   }

   $cmd or throw 'No restore command for driver '.$self->driver;

   return $cmd;
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

   $self->run_cmd( $self->$_backup_command( $path ) );

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

sub create_column : method {
   my $self     = shift;
   my $table_id = $self->next_argv or throw Unspecified, [ 'table id' ];
   my $name     = $self->next_argv or throw Unspecified, [ 'column name' ];
   my $ud_table = $self->schema->resultset( 'UserTable' )->find( $table_id )
      or throw 'Table id [_1] unknown', [ $table_id ];
   my $col_rs   = $self->schema->resultset( 'UserColumn' );
   my $column   = $col_rs->find( $table_id, $name );
   my $ddl      = "alter table ${ud_table} add ${name} ".$column->data_type;

   defined $column->size and $ddl .= '('.$column->size.')';

   $ddl .= $column->nullable ? ' null' : ' not null';

   defined $column->default_value
       and $ddl .= " default '".$column->default_value."'";

   $self->execute_ddl( $ddl, $self->$_table_connect_attr );

   return OK;
}

sub create_ddl : method {
   my $self = shift; $self->db_attr->{ignore_version} = TRUE;

   return $self->SUPER::create_ddl;
}

sub create_table : method {
   my $self     = shift;
   my $table_id = $self->next_argv or throw Unspecified, [ 'table id' ];
   my $ud_table = $self->schema->resultset( 'UserTable' )->find( $table_id )
      or throw 'Table id [_1] unknown', [ $table_id ];
   my $args     = [ $self, $ud_table ];
   my $sqlt     = $self->sqlt_class->new
      ( data              => \$args,
        no_comments       => TRUE,
        parser            => $_create_table,
        producer          => $self->driver2producer->{ lc $self->driver },
        quote_identifiers => FALSE );
   my $ddl      = $sqlt->translate or throw $sqlt->error;

   $self->execute_ddl( $ddl, $self->$_table_connect_attr );

   return OK;
}

sub deploy_and_populate : method {
   my $self = shift; $self->db_attr->{ignore_version} = TRUE;
   my $rv   = $self->SUPER::deploy_and_populate;

   $self->dry_run and return $rv;

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

sub drop_column : method {
   my $self        = shift;
   my $table_name  = $self->next_argv or throw Unspecified, [ 'table name' ];
   my $column_name = $self->next_argv or throw Unspecified, [ 'column name' ];
   my $ddl         = "alter table ${table_name} drop ${column_name};";

   $self->execute_ddl( $ddl, $self->$_table_connect_attr );

   return OK;
}

sub drop_table : method {
   my $self       = shift;
   my $table_name = $self->next_argv or throw Unspecified, [ 'table name' ];
   my $ddl        = "drop table if exists ${table_name};";
   my $r          = $self->execute_ddl( $ddl, $self->$_table_connect_attr );

   return OK;
}

sub dump_connect_attr : method {
   my $self = shift;
   my $db   = $self->database;
   my $attr = $db eq 'schedule'  ? $self->schema_connect_attr
            : $db eq 'usertable' ? $self->table_schema_connect_attr
            : throw 'Database [_1] unknown', [ $db ];

   $self->dumper( $attr );
   return OK;
}

sub restore_data : method {
   my $self = shift; my $conf = $self->config;

   my $path = $self->next_argv or throw Unspecified, [ 'file name' ];

   $path = io $path; $path->exists or throw PathNotFound, [ $path ];

   chdir $conf->appldir; ensure_class_loaded 'Archive::Tar';

   my $arc = Archive::Tar->new; $arc->read( $path->pathname ); $arc->extract();

   my $file = $path->basename( '.tgz' );
   my (undef, $date) = split m{ - }mx, $file, 2;
   my $bdir = $conf->vardir->catdir( 'backups' );
   my $sql  = $conf->tempdir->catfile( $self->database."-${date}.sql" );

   if ($sql->exists) {
      $self->run_cmd( $self->$_restore_command( $sql ) );
      $sql->unlink;
   }

   my $ver = $self->schema->get_db_version;
   my $message = "action:restore-data relpath:${file} schema_version:${ver}";

   $self->send_event( $self->$_new_request, $message );
   $self->info( 'Restored backup [_1] schema [_1]', { args => [ $file, $ver ]});

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

=head2 C<create_column> - Creates a user defined database table column

=head2 C<create_ddl> - Dump the database schema definition

Creates the DDL for multiple RDBMs

=head2 C<create_table> - Creates a user defined database table

=head2 C<deploy_and_populate> - Create tables and populates them with initial data

=head2 C<drop_column> - Drops a user defined database table column

=head2 C<drop_table> - Drops a user defined database table

=head2 C<dump_connect_attr> - Displays database connection information

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
