package App::Notitia::Schema::Schedule::ResultSet::Event;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( to_dt );
use Class::Usul::Functions  qw( throw );

# Private methods
my $_find_event_type = sub {
   my ($self, $type_name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_event_by( $type_name );
};

my $_find_owner = sub {
   my ($self, $scode) = @_; my $schema = $self->result_source->schema;

   my $opts = { columns => [ 'id' ] };

   return $schema->resultset( 'Person' )->find_by_shortcode( $scode, $opts );
};

my $_find_rota = sub {
   return $_[ 0 ]->result_source->schema->resultset( 'Rota' )->find_rota
      (   $_[ 1 ], $_[ 2 ] );
};

my $_find_vehicle = sub {
   my ($self, $vrn) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Vehicle' )->find_vehicle_by( $vrn );
};

# Public methods
sub new_result {
   my ($self, $columns) = @_;

   my $name = delete $columns->{rota}; my $date = delete $columns->{start_date};

   $name and $date
         and $columns->{start_rota_id} = $self->$_find_rota( $name, $date )->id;

   $date = delete $columns->{end_date};

   $name and $date
         and $columns->{end_rota_id} = $self->$_find_rota( $name, $date )->id;

   my $type = delete $columns->{event_type};

   $type and $columns->{event_type_id} = $self->$_find_event_type( $type )->id;

   my $owner = delete $columns->{owner};

   $owner and $columns->{owner_id} = $self->$_find_owner( $owner )->id;

   my $vrn = delete $columns->{vehicle};

   $vrn and $columns->{vehicle_id} = $self->$_find_vehicle( $vrn )->id;

   return $self->next::method( $columns );
}

sub count_events_for {
   my ($self, $rota_type_id, $start_date, $event_type) = @_;

   my $parser = $self->result_source->schema->datetime_parser;

   $event_type //= 'person'; $start_date = to_dt $start_date;

   return $self->count
      ( { 'event_type.name'    => $event_type,
          'start_rota.type_id' => $rota_type_id,
          'start_rota.date'    => $parser->format_datetime( $start_date ) },
        { join                 => [ 'start_rota', 'event_type' ] } );
}

sub find_event_by {
   my ($self, $uri, $opts) = @_; $opts //= {};

   $opts->{prefetch} //= []; push @{ $opts->{prefetch} }, 'start_rota';

   my $event = $self->search( { uri => $uri }, $opts )->single;

   defined $event or throw 'Event [_1] unknown', [ $uri ], level => 2;

   return $event;
}

sub search_for_a_days_events {
   my ($self, $rota_type_id, $start_date, $event_type) = @_;

   my $parser = $self->result_source->schema->datetime_parser;

   $event_type //= 'person'; $start_date = to_dt $start_date;

   return $self->search
      ( { 'event_type.name'    => $event_type,
          'start_rota.type_id' => $rota_type_id,
          'start_rota.date'    => $parser->format_datetime( $start_date ) },
        { columns => [ 'id', 'name', 'start_rota.date',
                       'start_rota.type_id', 'uri' ],
          join    => [ 'start_rota', 'event_type' ] } );
}

sub search_for_events {
   my ($self, $opts) = @_; my $where = {}; $opts = { %{ $opts // {} } };

   my $type   = delete $opts->{event_type};
      $type and $where->{ 'event_type.name' } = $type;
   my $vrn    = delete $opts->{vehicle};
      $vrn  and $where->{ 'vehicle.vrn' } = $vrn;
   my $parser = $self->result_source->schema->datetime_parser;

   if (my $after  = delete $opts->{after}) {
      $where->{ 'start_rota.date' } =
              { '>' => $parser->format_datetime( $after ) };
      $opts->{order_by} //= 'start_rota.date';
   }

   if (my $before = delete $opts->{before}) {
      $where->{ 'start_rota.date' } =
              { '<' => $parser->format_datetime( $before ) };
   }

   if (my $ondate = delete $opts->{on}) {
      $where->{ 'start_rota.date' } = $parser->format_datetime( $ondate );
   }

   $opts->{order_by} //= { -desc => 'start_rota.date' };

   my $prefetch = delete $opts->{prefetch} // [ 'end_rota', 'start_rota' ];

   $type and push @{ $prefetch }, 'event_type';
   $vrn  and push @{ $prefetch }, 'vehicle';

   my $fields = delete $opts->{fields} // {};

   return $self->search
      ( $where, { columns  => [ 'end_time', 'name', 'start_time', 'uri' ],
                  prefetch => $prefetch, %{ $opts } } );
}

sub search_for_vehicle_events {
   my ($self, $opts) = @_; $opts->{event_type} = 'vehicle';

   return $self->search_for_events( $opts );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Event - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Event;
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
