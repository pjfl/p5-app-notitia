package App::Notitia::Schema::Schedule::Result::UserForm;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent 'App::Notitia::Schema::Schedule::Base::Result';

use App::Notitia::Constants qw( FALSE NUL SPC TRUE VARCHAR_MAX_SIZE );
use App::Notitia::DataTypes qw( foreign_key_data_type serial_data_type
                                varchar_data_type );
use App::Notitia::Util      qw( from_json to_json );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'user_form' );

$class->add_columns
   ( id   => serial_data_type,
     table_id => foreign_key_data_type,
     name => varchar_data_type( 64 ),
     uri_prefix => varchar_data_type( 64 ),
     partial_uri => varchar_data_type( 64 ),
     template => varchar_data_type( 64 ),
     notes => varchar_data_type,
     response => varchar_data_type,
     content => {
        accessor      => '_content',
        data_type     => 'text',
        default_value => NUL,
        is_nullable   => FALSE, },
     );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'name' ] );

$class->belongs_to( table => "${result}::UserTable", 'table_id' );

$class->has_many( fields => "${result}::UserField", 'form_id' );

# Private methods
sub _as_string {
   return $_[ 0 ]->name;
}

sub content {
   my ($self, $k, $v) = @_;

   my $content = $self->{_content_cache}
             //= from_json( $self->_content || '{}' );

   defined $k or return $content; defined $v or return $content->{ $k };

   return $content->{ $k } = $v;
}

sub insert {
   my $self = shift;

   $self->_content( to_json $self->content );

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   return $self->next::method;
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $self->_content( to_json $self->content );
   $self->validate( TRUE );

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints    => {
         name        => { max_length => 64, min_length => 3, },
         notes       => { max_length => VARCHAR_MAX_SIZE(), min_length => 0 },
         template    => { max_length => 64, min_length => 3, },
      },
      fields         => {
         name        => {
            unique   => TRUE,
            filters  => 'filterWhiteSpace filterLowerCase',
            validate => 'isMandatory isValidLength isValidIdentifier' },
         notes       => { validate => 'isValidLength isValidText' },
         table_id    => { validate => 'isMandatory isValidInteger' },
         template    => { validate => 'isValidLength isValidText' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::UserForm - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::UserForm;
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
