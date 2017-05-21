package App::Notitia::Schema::Schedule::Result::UserTable;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent 'App::Notitia::Schema::Schedule::Base::Result';

use App::Notitia::Constants qw( SPC TRUE );
use App::Notitia::DataTypes qw( serial_data_type varchar_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'user_table' );

$class->add_columns
   ( id   => serial_data_type,
     name => varchar_data_type( 64 ),
     );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'name' ] );

$class->has_many( forms   => "${result}::UserForm",   'table_id' );
$class->has_many( columns => "${result}::UserColumn", 'table_id' );

# Private functions
my $_add_id_column = sub {
   my ($schema, $id) = @_; my $rs = $schema->resultset( 'UserColumn' );

   return $rs->find_or_create( {
      data_type => 'integer', name => 'id', table_id => $id } );
};

my $_queue_table_job = sub {
   my ($schema, $action, $id) = @_;

   my $name    = "${action}_table";
   my $binsdir = $schema->config->binsdir;
   my $cmd     = $binsdir->catfile( 'notitia-schema' )." ${name} ${id}";
   my $rs      = $schema->resultset( 'Job' );

   return $rs->create( { command => $cmd, max_runs => 1, name => $name } );
};

# Private methods
sub _as_string {
   return $_[ 0 ]->name;
}

# Public methods
sub delete {
   my $self   = shift;
   my $schema = $self->result_source->schema;
   my $guard  = $schema->txn_scope_guard;
   my $name   = $self->name;
   my $r      = $self->next::method;

   $_queue_table_job->( $schema, 'drop', $name );
   $guard->commit;

   return $r;
}

sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   my $schema = $self->result_source->schema;
   my $guard  = $schema->txn_scope_guard;
   my $table  = $self->next::method;
   my $id     = $table->id;

   $_add_id_column->( $schema, $id );
   $_queue_table_job->( $schema, 'create', $id );
   $guard->commit;

   return $table;
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $self->validate( TRUE );

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints    => {
         name        => { max_length => 64, min_length => 1, },
      },
      fields         => {
         name        => {
            unique   => TRUE,
            validate => 'isMandatory isValidLength isValidIdentifier' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Table - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Table;
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
