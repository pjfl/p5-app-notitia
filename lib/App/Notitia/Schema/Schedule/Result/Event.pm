package App::Notitia::Schema::Schedule::Result::Event;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( VARCHAR_MAX_SIZE TRUE );
use App::Notitia::Util      qw( foreign_key_data_type
                                nullable_foreign_key_data_type
                                serial_data_type varchar_data_type );
use Class::Usul::Functions  qw( create_token );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'event' );

$class->add_columns
   ( id            => serial_data_type,
     event_type_id => foreign_key_data_type,
     owner_id      => foreign_key_data_type,
     start_rota_id => foreign_key_data_type,
     end_rota_id   => nullable_foreign_key_data_type,
     vehicle_id    => nullable_foreign_key_data_type,
     start_time    => varchar_data_type(   5 ),
     end_time      => varchar_data_type(   5 ),
     name          => varchar_data_type(  57 ),
     uri           => varchar_data_type(  64 ),
     description   => varchar_data_type( 128 ),
     notes         => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'uri' ] );

$class->belongs_to( event_type => "${result}::Type",   'event_type_id' );
$class->belongs_to( owner      => "${result}::Person", 'owner_id' );
$class->belongs_to( start_rota => "${result}::Rota",   'start_rota_id' );
$class->belongs_to( end_rota   =>
                    "${result}::Rota", 'end_rota_id', $left_join );
$class->belongs_to( vehicle    =>
                    "${result}::Vehicle", 'vehicle_id', $left_join );

$class->has_many( participents     => "${result}::Participent",    'event_id' );
$class->has_many( vehicle_requests => "${result}::VehicleRequest", 'event_id' );
$class->has_many( transports       => "${result}::Transport",      'event_id' );

# Private methods
sub _as_string {
   return $_[ 0 ]->uri;
}

my $_set_uri = sub {
   my $self    = shift;
   my $columns = { $self->get_inflated_columns };
   my $rota_id = $columns->{start_rota_id};
   my $name    = lc $columns->{name}; $name =~ s{ [ ] }{-}gmx;
   my $token   = lc substr create_token( $name.$rota_id ), 0, 6;

   $columns->{uri} = "${name}-${token}";
   $self->set_inflated_columns( $columns );
   return;
};

# Public methods
sub end_date {
   my $self = shift; my $end = $self->end_rota;

   return defined $end ? $end->date : $self->start_date;
}

sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   $self->$_set_uri;

   return $self->next::method;
}

sub label {
   my $self = shift; my $date = $self->start_rota->date->clone;

   return $self->name.' ('.$date->set_time_zone( 'local' )->dmy( '/' ).')';
}

sub post_filename {
   my $self = shift; my $date = $self->start_rota->date->clone;

   return $date->set_time_zone( 'local' )->ymd.'_'.$self->uri;
}

sub start_date {
   return $_[ 0 ]->start_rota->date;
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $self->validate( TRUE );
   $self->$_set_uri;

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints    => {
         description => { max_length => 128, min_length =>  5, },
         end_time    => { max_length =>   5, min_length =>  0,
                          pattern    => '\A \d\d : \d\d (?: : \d\d )? \z', },
         name        => { max_length =>  57, min_length =>  3, },
         notes       => { max_length =>  VARCHAR_MAX_SIZE(), min_length => 0, },
         start_time  => { max_length =>   5, min_length =>  0,
                          pattern    => '\A \d\d : \d\d (?: : \d\d )? \z', },
      },
      fields         => {
         description => {
            filters  => 'filterUCFirst',
            validate => 'isMandatory isValidLength isValidText' },
         end_time    => {
            validate => 'isMandatory isValidLength isMatchingRegex' },
         name        => {
            filters  => 'filterTitleCase',
            validate => 'isMandatory isValidLength isSimpleText' },
         notes       => { validate => 'isValidLength isValidText' },
         start_time  => {
            validate => 'isMandatory isValidLength isMatchingRegex' },
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
