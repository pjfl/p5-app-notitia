package App::Notitia::Role::Navigation;

use attributes ();
use namespace::autoclean;

use App::Notitia::Constants qw( FALSE TRUE );
use App::Notitia::Util      qw( loc to_dt uri_for_action );
use Class::Usul::Functions  qw( is_member );
use Class::Usul::Time       qw( time2str );
use DateTime                qw( );
use Moo::Role;

requires qw( components list_roles );

# Private functions
my $_list_roles_of = sub {
   my $attr = attributes::get( shift ) // {}; return $attr->{Role} // [];
};

my $nav_folder = sub {
   return { depth => $_[ 2 ] // 0,
            title => loc( $_[ 0 ], $_[ 1 ].'_management_heading' ),
            type  => 'folder', };
};

my $nav_linkto = sub {
   my ($req, $opts, $actionp, @args) = @_; my $name = $opts->{name};

   my $depth      = $opts->{depth} // 1;
   my $label_opts = { params => $opts->{label_args} // [],
                      no_quote_bind_values => TRUE, };
   my $label      = loc $req, $opts->{label} // "${name}_link", $label_opts;
   my $tip        = loc $req, $opts->{tip} // "${name}_tip";
   my $uri        = uri_for_action $req, $actionp, @args;

   return { depth => $depth, label => $label,
            tip   => $tip,   type  => 'link', uri => $uri, };
};

my $_week_link = sub {
   my ($req, $actionp, $name, $date) = @_;

   my $tip    = 'Navigate to this week';
   my $label  = 'Week '.$date->week_number;
   my $opts   = { label => $label, name => 'wk'.$date->week_number,
                  tip   => $tip };
   my $args   = [ $name, $date->ymd ];
   my $params = { rota_date => $date->ymd };

   return $nav_linkto->( $req, $opts, $actionp, $args, $params );
};

my $_year_link = sub {
   my ($req, $actionp, $name, $date) = @_;

   my $tip    = 'Navigate to this year';
   my $opts   = { label => $date->year, name => $date->year, tip => $tip };
   my $args   = [ $name, $date->ymd ];
   my $params = { rota_date => $date->ymd };

   return $nav_linkto->( $req, $opts, $actionp, $args, $params );
};

# Private methods
my $_allowed = sub {
   my ($self, $roles, $actionp) = @_;

   my ($moniker, $method) = split m{ / }mx, $actionp, 2;
   my $model        = $self->components->{ $moniker };
   my $method_roles = $_list_roles_of->( $model->can( $method ) );

   is_member 'anon', $method_roles and return TRUE;
   is_member 'any',  $method_roles and return TRUE;

   for my $role_name (@{ $roles }) {
      is_member $role_name, $method_roles and return TRUE;
   }

   return FALSE;
};

# Public methods
sub admin_navigation_links {
   my ($self, $req) = @_;

   my ($roles) = $self->list_roles( $req ); my $now = DateTime->now;

   my $nav =
      [ $nav_folder->( $req, 'events' ),
        $nav_linkto->( $req, { name => 'current_events' }, 'event/events', [],
                       after  => $now->clone->subtract( days => 1 )->ymd ),
        $nav_linkto->( $req, { name => 'previous_events' }, 'event/events', [],
                       before => $now->ymd ),
        $nav_folder->( $req, 'people' ), ];

   $self->$_allowed( $roles, 'person/contacts' ) and push @{ $nav },
        $nav_linkto->( $req, { name => 'contacts_list' }, 'person/contacts', [],
                       status => 'current' );

   push @{ $nav },
        $nav_linkto->( $req, { name => 'people_list' }, 'person/people', [] ),
        $nav_linkto->( $req, { name => 'current_people_list' }, 'person/people',
                       [], status => 'current' ),
        $nav_linkto->( $req, { name => 'bike_rider_list' }, 'person/people',
                       [], role => 'bike_rider', status => 'current' ),
        $nav_linkto->( $req, { name => 'controller_list' }, 'person/people',
                       [], role => 'controller', status => 'current' ),
        $nav_linkto->( $req, { name => 'driver_list' }, 'person/people',
                       [], role => 'driver', status => 'current' ),
        $nav_linkto->( $req, { name => 'fund_raiser_list' }, 'person/people',
                       [], role => 'fund_raiser', status => 'current' );

   if ($self->$_allowed( $roles, 'admin/types' )) {
      push @{ $nav },
        $nav_folder->( $req, 'types' ),
        $nav_linkto->( $req, { name => 'types_list' }, 'admin/types', [] ),
        $nav_linkto->( $req, { name => 'slot_roles_list' },
                       'admin/slot_roles', [] ),
   }

   if ($self->$_allowed( $roles, 'asset/vehicles' )) {
      push @{ $nav },
        $nav_folder->( $req, 'vehicles' ),
        $nav_linkto->( $req, { name => 'vehicles_list' },
                       'asset/vehicles', [] ),
        $nav_linkto->( $req, { name => 'service_vehicles' },
                       'asset/vehicles', [], service => TRUE ),
        $nav_linkto->( $req, { name => 'private_vehicles' },
                       'asset/vehicles', [], private => TRUE );
   }

   return $nav;
}

sub rota_navigation_links {
   my ($self, $req, $period, $name) = @_;

   my $actionp = "sched/${period}_rota"; my $date = $req->session->rota_date;

   $date or $req->session->rota_date( $date = time2str '%Y-%m-01', 'GMT' );

   my $now = to_dt( $date, 'GMT' )->set_time_zone( 'floating' )
                                  ->truncate( to => 'day' )->set( day => 1 );

   my $nav = [ $nav_folder->( $req, 'months' ) ];

   for my $mno (0 .. 11) {
      my $offset = $mno - 5;
      my $month  = $offset > 0 ? $now->clone->add( months => $offset )
                 : $offset < 0 ? $now->clone->subtract( months => -$offset )
                 :               $now->clone;
      my $opts   = { label_args => [ $month->year ],
                     name       => lc 'month_'.$month->month_abbr };
      my $args   = [ $name, $month->ymd ];

      push @{ $nav }, $nav_linkto->( $req, $opts, $actionp, $args );
   }

   push @{ $nav }, $nav_folder->( $req, 'year' );
   $date = $now->clone->subtract( years => 1 );
   push @{ $nav }, $_year_link->( $req, $actionp, $name, $date );
   $date = $now->clone->add( years => 1 );
   push @{ $nav }, $_year_link->( $req, $actionp, $name, $date );

   $actionp = "sched/week_rota";
   $now     = to_dt( time2str( '%Y-%m-%d' ), 'GMT' )->truncate( to => 'day' );
   push @{ $nav }, $nav_folder->( $req, 'week' );
   $date = $now->clone->subtract( weeks => 1 );
   push @{ $nav }, $_week_link->( $req, $actionp, $name, $date );
   $date = $now->clone;
   push @{ $nav }, $_week_link->( $req, $actionp, $name, $date );
   $date = $now->clone->add( weeks => 1 );
   push @{ $nav }, $_week_link->( $req, $actionp, $name, $date );

   return $nav;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::Navigation - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::Navigation;
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
