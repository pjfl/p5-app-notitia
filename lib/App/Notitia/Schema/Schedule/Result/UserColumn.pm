package App::Notitia::Schema::Schedule::Result::UserColumn;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent 'App::Notitia::Schema::Schedule::Base::Result';

use App::Notitia::Constants qw( DATA_TYPE_ENUM FALSE TRUE );
use App::Notitia::DataTypes qw( bool_data_type enumerated_data_type
                                foreign_key_data_type nullable_varchar_data_type
                                numerical_id_data_type serial_data_type
                                varchar_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'user_column' );

$class->add_columns
   ( table_id      => foreign_key_data_type,
     name          => varchar_data_type( 64 ),
     data_type     => enumerated_data_type( DATA_TYPE_ENUM, 'varchar' ),
     default_value => nullable_varchar_data_type,
     size          => numerical_id_data_type,
     nullable      => bool_data_type( FALSE ),
     );

$class->set_primary_key( 'table_id', 'name' );

$class->belongs_to( table => "${result}::UserTable", 'table_id' );

# Private functions
my $_queue_column_job = sub {
   my ($schema, $action, $table_id, $column_name) = @_;

   my $name    = "${action}_column";
   my $binsdir = $schema->config->binsdir;
   my $cmd     = $binsdir->catfile( 'notitia-schema' )
               . " ${name} ${table_id} ${column_name}";
   my $rs      = $schema->resultset( 'Job' );

   return $rs->create( { command => $cmd, max_runs => 1, name => $name } );
};

# Private methods
sub _as_string {
   return $_[ 0 ]->table.'.'.$_[ 0 ]->name;
}

# Public methods
sub delete {
   my $self   = shift;
   my $schema = $self->result_source->schema;
   my $guard  = $schema->txn_scope_guard;
   my $r      = $self->next::method;

   $_queue_column_job->( $schema, 'drop', $self->table->name, $self->name );
   $guard->commit;

   return $r;
}

sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   my $schema = $self->result_source->schema;
   my $guard  = $schema->txn_scope_guard;
   my $column = $self->next::method;

   $_queue_column_job->( $schema, 'create', $column->table_id, $column->name );
   $guard->commit;

   return $column;
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

App::Notitia::Schema::Schedule::Result::Column - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Column;
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
