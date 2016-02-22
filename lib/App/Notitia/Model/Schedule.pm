package App::Notitia::Model::Schedule;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS NUL SHIFT_TYPE_ENUM SPC TRUE );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Types      qw( LoadableClass Object );
use Class::Usul::Time       qw( str2date_time time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);

# Attribute constructors
my $_build_schema = sub {
   my $self = shift; my $extra = $self->config->connect_params;

   $self->schema_class->config( $self->config );

   return $self->schema_class->connect( @{ $self->get_connect_info }, $extra );
};

my $_build_schema_class = sub {
   return $_[ 0 ]->config->schema_classes->{ $_[ 0 ]->config->database };
};

# Public attributes
has '+moniker'     => default => 'sched';

has 'schema'       => is => 'lazy', isa => Object,
   builder         => $_build_schema;

has 'schema_class' => is => 'lazy', isa => LoadableClass,
   builder         => $_build_schema_class;

# Private class attributes
my $_rota_types_id = {};
my $_translations  = {};

# Private functions
my $_loc = sub {
   my ($req, $k) = @_; $_translations->{ my $locale = $req->locale } //= {};

   return exists $_translations->{ $locale }->{ $k }
               ? $_translations->{ $locale }->{ $k }
               : $_translations->{ $locale }->{ $k } = $req->loc( $k );
};

my $_headers = sub {
   return [ map { { val => $_loc->( $_[ 0 ], "rota_heading_${_}" ) } } 0 .. 4 ];
};

my $_events = sub {
   my ($req, $rota, $rota_dt, $todays_events) = @_;

   my $events = $rota->{events};
   my $date   = $rota_dt->day_abbr.SPC.$rota_dt->day;

   push @{ $events }, [ { val     => $date, class => 'rota-date' },
                        { val     => ucfirst( $todays_events->next // NUL ),
                          colspan => 4 } ];

   while (defined (my $event = $todays_events->next)) {
      push @{ $events }, [ { val => undef },
                           { val => ucfirst( $event ), colspan => 4 } ];
   }

   return;
};

my $_controllers = sub {
   my ($req, $rota, $slot_rows, $limits) = @_;

   my $shift_no = 0; my $controls = $rota->{controllers};

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $max_slots = $limits->[ $shift_no++ ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k = "${shift_type}_controller_${subslot}";

         push @{ $controls },
            [ { val => $_loc->( $req, $k ), class => 'rota-header' },
              { val => $slot_rows->{ $k }, colspan => 4 } ];
      }
   }

   return;
};

my $_riders_n_drivers = sub {
   my ($req, $rota, $slot_rows, $limits) = @_;

   my $shift_no = 0; my $shifts = $rota->{shifts};

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $max_slots = $limits->[ 2 + $shift_no ];
      my $shift     = $shifts->[ $shift_no ] = {};
      my $riders    = $shift->{riders } = [];
      my $drivers   = $shift->{drivers} = [];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k = "${shift_type}_rider_${subslot}";

         push @{ $riders },
            [ { val   => $_loc->( $req, $k ), class => 'rota-header' },
              { val   => $slot_rows->{ $k }->{vehicle }, class => 'narrow' },
              { val   => $slot_rows->{ $k }->{operator} },
              { val   => $slot_rows->{ $k }->{bike_req},
                class => 'centre narrow' },
              { val   => $slot_rows->{ $k }->{ops_veh }, class => 'narrow' }, ];
      }

      $max_slots = $limits->[ 4 + $shift_no ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k = "${shift_type}_driver_${subslot}";

         push @{ $drivers },
            [ { val => $_loc->( $req, $k ), class => 'rota-header' },
              { val => undef },
              { val => $slot_rows->{ $k }->{operator} },
              { val => undef, class => 'narrow' },
              { val => $slot_rows->{ $k }->{ops_veh }, class => 'narrow' }, ];
      }

      $shift_no++;
   }

   return;
};

my $_get_page = sub {
   my ($req, $rota_name, $rota_date, $todays_events, $slot_rows, $limits) = @_;

   my $rota_dt =  str2date_time $rota_date;
   my $title   =  ucfirst( $_loc->( $req, $rota_name ) ).SPC
               .  $_loc->( $req, 'rota for' ).SPC.$rota_dt->month_name;
   my $page    =  {
      rota     => { controllers => [],
                    events      => [],
                    headers     => $_headers->( $req ),
                    shifts      => [], },
      template => [ 'nav_panel', 'rota' ],
      title    => $title };
   my $rota    =  $page->{rota};

   $_events->( $req, $rota, $rota_dt, $todays_events );
   $_controllers->( $req, $rota, $slot_rows, $limits );
   $_riders_n_drivers->( $req, $rota, $slot_rows, $limits );

   return $page;
};

my $_operators_vehicle = sub {
   my $slot    = shift;
   my $pv      = $slot->personal_vehicles->first;
   my $pv_type = $pv ? $pv->type : NUL;

   return $pv_type eq '4x4' ? $pv_type
        : $pv_type eq 'car' ? ucfirst( $pv_type ) : undef;
};

# Private methods
my $_find_rota_type_id_for = sub {
   exists $_rota_types_id->{ $_[ 1 ] } or $_rota_types_id->{ $_[ 1 ] }
      = $_[ 0 ]->schema->resultset( 'Type' )->search
         ( { name    => $_[ 1 ], type => 'rota' },
           { columns => [ 'id' ] } )->single->id;

   return $_rota_types_id->{ $_[ 1 ] };
};

# Public methods
sub get_content {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $today     = time2str '%Y-%m-%d';
   my $name      = $params->( 0, { optional => TRUE } ) // 'main';
   my $date      = $params->( 1, { optional => TRUE } ) // $today;
   my $type_id   = $self->$_find_rota_type_id_for( $name );
   my $slot_rs   = $self->schema->resultset( 'Slot' );
   my $slots     = $slot_rs->search
      ( { 'rota.type_id' => $type_id, 'rota.date' => $date },
        { columns  => [ qw( bike_requested operator.name
                            type vehicle.name subslot ) ],
          join     => [ { 'shift' => 'rota' }, 'operator', 'vehicle', ],
          prefetch => [ { 'shift' => 'rota' }, 'operator', 'vehicle',
                        'personal_vehicles' ] } );
   my $event_rs  = $self->schema->resultset( 'Event' );
   my $events    = $event_rs->search
      ( { 'rota.type_id' => $type_id, 'rota.date' => $date },
        { columns  => [ 'name' ], join => [ 'rota' ] } );
   my $limits    = $self->config->slot_limits;
   my $slot_rows = {};

   for my $slot ($slots->all) {
      $slot_rows->{ $slot->shift->type.'_'.$slot->type.'_'.$slot->subslot }
         = { vehicle  =>  $slot->vehicle,
             operator =>  $slot->operator,
             bike_req => ($slot->bike_requested ? 'Y' : 'N'),
             ops_veh  =>  $_operators_vehicle->( $slot ) };
   }

   my $page = $_get_page->( $req, $name, $date, $events, $slot_rows, $limits );

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Schedule - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Schedule;
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
