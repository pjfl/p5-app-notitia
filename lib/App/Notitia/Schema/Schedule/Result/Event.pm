package App::Notitia::Schema::Schedule::Result::Event;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( VARCHAR_MAX_SIZE TRUE );
use App::Notitia::DataTypes qw( foreign_key_data_type
                                nullable_foreign_key_data_type
                                nullable_numerical_id_data_type
                                serial_data_type varchar_data_type );
use App::Notitia::Util      qw( local_dt locd locm );
use Class::Usul::Functions  qw( create_token exception throw );
use Unexpected::Functions   qw( ValidationErrors );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'event' );

$class->add_columns
   ( id               => serial_data_type,
     event_type_id    => foreign_key_data_type,
     owner_id         => foreign_key_data_type,
     start_rota_id    => foreign_key_data_type,
     end_rota_id      => nullable_foreign_key_data_type,
     vehicle_id       => nullable_foreign_key_data_type,
     course_type_id   => nullable_foreign_key_data_type,
     location_id      => nullable_foreign_key_data_type,
     max_participents => nullable_numerical_id_data_type,
     start_time       => varchar_data_type(   5 ),
     end_time         => varchar_data_type(   5 ),
     name             => varchar_data_type(  57 ),
     uri              => varchar_data_type(  64 ),
     description      => varchar_data_type( 128 ),
     notes            => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'uri' ] );

$class->belongs_to( event_type => "${result}::Type",   'event_type_id' );
$class->belongs_to( owner      => "${result}::Person", 'owner_id' );
$class->belongs_to( start_rota => "${result}::Rota",   'start_rota_id' );
$class->belongs_to( end_rota   =>
                    "${result}::Rota", 'end_rota_id', $left_join );
$class->belongs_to( vehicle    =>
                    "${result}::Vehicle", 'vehicle_id', $left_join );
$class->belongs_to( course_type =>
                    "${result}::Type", 'course_type_id', $left_join );
$class->belongs_to( location   =>
                    "${result}::Location", 'location_id', $left_join );

$class->has_many( participents     => "${result}::Participent",    'event_id' );
$class->has_many( vehicle_requests => "${result}::VehicleRequest", 'event_id' );
$class->has_many( trainers         => "${result}::Trainer",        'event_id' );
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

my $_vehicle_event_id_cache;

my $_vehicle_event_id = sub {
   my $self = shift;

   $_vehicle_event_id_cache and return $_vehicle_event_id_cache;

   my $schema = $self->result_source->schema;
   my $type = $schema->resultset( 'Type' )->find_event_by( 'vehicle' );

   return $_vehicle_event_id_cache = $type->id;
};

my $_assert_event_allowed = sub {
   my $self = shift;

   $self->starts > $self->ends
      and throw ValidationErrors, [ exception 'Ends before start' ];

   $self->event_type_id == $self->$_vehicle_event_id or return;

   my $opts = { on => $self->start_date, vehicle => $self->vehicle };

   $self->assert_not_assigned_to_event( $self, $opts );
   $self->assert_not_assigned_to_slot( $self, $opts );
   $self->assert_not_assigned_to_vehicle_event( $self, $opts );
   return;
};

# Public methods
sub add_trainer {
   my ($self, $scode) = @_;

   my $schema = $self->result_source->schema;
   my $trainer = $schema->resultset( 'Person' )->find_by_shortcode( $scode );

   return $self->create_related( 'trainers', { trainer_id => $trainer->id } );
}

sub count_of_participents {
   my $self = shift;
   my $rs   = $self->result_source->schema->resultset( 'Participent' );

   return $rs->count( { event_id => $self->id } );
}

sub duration {
   return $_[ 0 ]->starts, $_[ 0 ]->ends;
}

sub end_date {
   return $_[ 0 ]->end_rota->date->clone;
}

sub ends {
   my $self = shift; my ($hours, $mins) = split m{ : }mx, $self->end_time, 2;

   return $self->end_date->add( hours => $hours )->add( minutes => $mins );
}

sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;
   $self->$_assert_event_allowed;
   $self->$_set_uri;

   return $self->next::method;
}

sub label {
   my ($self, $req) = @_; $req and return $self->localised_label( $req );

   return $self->name.' ('.local_dt( $self->start_date )->dmy( '/' ).')';
}

sub localised_label {
   my ($self, $req) = @_; my $name = locm $req, lc $self->name;

   $name = $name ne lc $self->name ? $name : $self->name;

   return $name.' ('.locd( $req, $self->start_date ).')';
}

sub post_filename {
   return local_dt( $_[ 0 ]->start_date )->ymd.'_'.$_[ 0 ]->uri;
}

sub remove_trainer {
   my ($self, $scode) = @_;

   my $schema = $self->result_source->schema;
   my $trainer = $schema->resultset( 'Person' )->find_by_shortcode( $scode );

   return $self->delete_related( 'trainers', { trainer_id => $trainer->id } );
}

sub sqlt_deploy_hook {
   my ($self, $sql) = @_;

   $sql->add_index( name => 'event_idx_event_type_id',
                    fields => [ 'event_type_id' ] );

   return;
}

sub start_date {
   return $_[ 0 ]->start_rota->date->clone;
}

sub starts {
   my $self = shift; my ($hours, $mins) = split m{ : }mx, $self->start_time, 2;

   return $self->start_date->add( hours => $hours )->add( minutes => $mins );
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $self->$_assert_event_allowed;
   $self->validate( TRUE );
   $self->$_set_uri;

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints    => {
         description => { max_length => 128, min_length =>  5, },
         end_time    => { max_length =>   5, min_length =>  0, },
         name        => { max_length =>  57, min_length =>  3, },
         notes       => { max_length =>  VARCHAR_MAX_SIZE(), min_length => 0, },
         start_time  => { max_length =>   5, min_length =>  0, },
      },
      fields         => {
         description => {
            filters  => 'filterUCFirst',
            validate => 'isMandatory isValidLength isValidText' },
         end_time    => {
            validate => 'isMandatory isValidLength isValidTime' },
         max_participents => { validate => 'isValidInteger' },
         name        => {
            filters  => 'filterTitleCase',
            validate => 'isMandatory isValidLength isSimpleText' },
         notes       => { validate => 'isValidLength isValidText' },
         start_time  => {
            validate => 'isMandatory isValidLength isValidTime' },
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
