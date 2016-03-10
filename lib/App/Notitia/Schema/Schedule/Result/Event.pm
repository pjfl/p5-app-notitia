package App::Notitia::Schema::Schedule::Result::Event;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( VARCHAR_MAX_SIZE );
use App::Notitia::Util      qw( date_data_type foreign_key_data_type
                                serial_data_type varchar_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'event' );

$class->add_columns
   ( id          => serial_data_type,
     rota_id     => foreign_key_data_type,
     owner_id    => foreign_key_data_type,
     start_time  => varchar_data_type(   5 ),
     end_time    => varchar_data_type(   5 ),
     name        => varchar_data_type(  64 ),
     description => varchar_data_type( 128 ),
     notes       => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'name', 'rota_id' ] );

$class->belongs_to( rota  => "${result}::Rota", 'rota_id' );
$class->belongs_to( owner => "${result}::Person", 'owner_id', $left_join );

$class->has_many( participents => "${result}::Participent", 'event_id' );
$class->has_many( transports   => "${result}::Transport",   'event_id' );

# Private methods
sub _as_string {
   return $_[ 0 ]->name;
}

# Public methods
sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   return $self->next::method;
}

sub label {
   return $_[ 0 ]->name.' ('.$_[ 0 ]->rota->date->dmy.')';
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns ); $self->validate;

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints    => {
         description => { max_length => 128, min_length => 10, },
         end_time    => { max_length =>   5, min_length =>  0,
                          pattern    => '\A \d\d : \d\d (?: : \d\d )? \z', },
         name        => { max_length =>  64, min_length =>  3, },
         notes       => { max_length =>  VARCHAR_MAX_SIZE(), min_length => 0, },
         start_time  => { max_length =>   5, min_length =>  0,
                          pattern    => '\A \d\d : \d\d (?: : \d\d )? \z', },
      },
      fields         => {
         description => {
            filters  => 'filterUCFirst',
            validate => 'isMandatory isValidLength isValidText' },
         end_time    => { validate => 'isValidLength isMatchingRegex' },
         name        => {
            filters  => 'filterTitleCase',
            validate => 'isMandatory isValidLength isSimpleText' },
         notes       => { validate => 'isValidLength isValidText' },
         end_time    => { validate => 'isValidLength isMatchingRegex' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Event - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Event;
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
