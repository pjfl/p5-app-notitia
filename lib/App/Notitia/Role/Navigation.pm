package App::Notitia::Role::Navigation;

use attributes ();
use namespace::autoclean;

use App::Notitia::Constants qw( FALSE HASH_CHAR NUL SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link p_button p_image p_item );
use App::Notitia::Util      qw( dialog_anchor locm make_tip
                                to_dt uri_for_action );
use Class::Usul::Functions  qw( is_member );
use Class::Usul::Time       qw( time2str );
use DateTime                qw( );
use Moo::Role;

requires qw( components );

# Private functions
my $_list_roles_of = sub {
   my $attr = attributes::get( shift ) // {}; return $attr->{Role} // [];
};

my $nav_folder = sub {
   return { depth => $_[ 2 ] // 0,
            title => locm( $_[ 0 ], $_[ 1 ].'_management_heading' ),
            type  => 'folder', };
};

my $nav_linkto = sub {
   my ($req, $opts, $actionp, @args) = @_; my $name = $opts->{name};

   my $depth = $opts->{depth} // 1;
   my $value = locm $req, $opts->{value} // "${name}_link",
                   @{ $opts->{value_args} // [] };
   my $tip   = locm $req, $opts->{tip} // "${name}_tip",
                   @{ $opts->{tip_args} // [] };
   my $href  = $actionp eq HASH_CHAR
             ? $actionp : uri_for_action $req, $actionp, @args;

   return { class => $opts->{class} // NUL,
            container_class => $opts->{container_class} // NUL,
            depth => $depth,
            hint  => locm( $req, 'Hint' ),
            href  => $href,
            name  => $name,
            tip   => $tip,
            type  => 'link',
            value => $value, };
};

my $_week_link = sub {
   my ($req, $actionp, $name, $date, $opts, $params) = @_;

   $opts //= {}; $params //= {};

   my $args = [ $name, $date->ymd ];
   my $tip = 'Navigate to week commencing [_1]';
   my $value = locm( $req, 'Week' ).SPC.$date->week_number;

   $opts = { value => $value,   name => 'wk'.$date->week_number,
             tip   => $tip, tip_args => [ $date->dmy( '/' ) ], %{ $opts } };
   $params->{rota_date} = $date->ymd;

   return $nav_linkto->( $req, $opts, $actionp, $args, $params );
};

my $_year_link = sub {
   my ($req, $actionp, $name, $date) = @_;

   my $tip    = 'Navigate to [_1]';
   my $opts   = { value => $date->year, name => $date->year,
                  tip   => $tip,    tip_args => [ $date->year ], };
   my $args   = [ $name, $date->ymd ];
   my $params = { rota_date => $date->ymd };

   return $nav_linkto->( $req, $opts, $actionp, $args, $params );
};

# Private methods
my $_allowed = sub {
   my ($self, $req, $actionp) = @_;

   my ($moniker, $method) = split m{ / }mx, $actionp, 2;
   my $model        = $self->components->{ $moniker };
   my $method_roles = $_list_roles_of->( $model->can( $method ) );

   is_member 'anon', $method_roles and return TRUE;
   $req->authenticated or return FALSE;
   is_member 'any',  $method_roles and return TRUE;

   for my $role_name (@{ $req->session->roles }) {
      is_member $role_name, $method_roles and return TRUE;
   }

   return FALSE;
};

my $_admin_people_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   my $is_allowed_contacts = $self->$_allowed( $req, 'person/contacts' );
   my $is_allowed_people = $self->$_allowed( $req, 'person/people' );

   ($is_allowed_contacts or $is_allowed_people)
      and push @{ $list }, $nav_folder->( $req, 'people' );

   $is_allowed_contacts and push @{ $list },
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'contacts_list' ? 'selected' : NUL,
         name => 'contacts_list' }, 'person/contacts', [],
                     status => 'current' );

   $is_allowed_people and push @{ $list },
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'people_list' ? 'selected' : NUL,
         name => 'people_list' }, 'person/people', [] ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'current_people_list' ? 'selected' : NUL,
         name => 'current_people_list' }, 'person/people',
                     [], status => 'current' ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'rider_list' ? 'selected' : NUL,
         name => 'rider_list' }, 'person/people',
                     [], role => 'rider', status => 'current' ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'controller_list' ? 'selected' : NUL,
         name => 'controller_list' }, 'person/people',
                     [], role => 'controller', status => 'current' ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'driver_list' ? 'selected' : NUL,
         name => 'driver_list' }, 'person/people',
                     [], role => 'driver', status => 'current' ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'fund_raiser_list' ? 'selected' : NUL,
         name => 'fund_raiser_list' }, 'person/people',
                     [], role => 'fund_raiser', status => 'current' );
   return;
};

my $_admin_vehicle_links = sub {
   my ($self, $req, $page, $nav) = @_; my $list = $nav->{menu}->{list};

   push @{ $list },
      $nav_folder->( $req, 'vehicles' ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'vehicles_list' ? 'selected' : NUL,
         name => 'vehicles_list' }, 'asset/vehicles', [] ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'service_vehicles' ? 'selected' : NUL,
         name => 'service_vehicles' },
                     'asset/vehicles', [], service => TRUE ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'private_vehicles' ? 'selected' : NUL,
         name => 'private_vehicles' },
                     'asset/vehicles', [], private => TRUE );
   return;
};

my $_rota_month_links = sub {
   my ($self, $req, $actionp, $name, $f_dom, $local_dt, $nav) = @_;

   my $list = $nav->{menu}->{list};

   push @{ $list }, $nav_folder->( $req, 'months' );

   for my $mno (0 .. 11) {
      my $offset = $mno - 5;
      my $date   = $offset > 0 ? $f_dom->clone->add( months => $offset )
                 : $offset < 0 ? $f_dom->clone->subtract( months => -$offset )
                 :               $f_dom->clone;
      my $opts   = {
         class      => $date->month == $local_dt->month ? 'selected' : NUL,
         name       => lc 'month_'.$date->month_abbr,
         tip_args   => [ $date->month_name ],
         value_args => [ $date->year ], };
      my $args   = [ $name, $date->ymd ];

      push @{ $list }, $nav_linkto->( $req, $opts, $actionp, $args );
   }

   return;
};

my $_rota_week_links = sub {
   my ($self, $req, $name, $sow, $nav) = @_;

   my $actionp = 'week/week_rota'; my $list = $nav->{menu}->{list};

   push @{ $list },
      $nav_folder->( $req, 'week' ),
      $_week_link->( $req, $actionp, $name,
                     $sow->clone->subtract( weeks => 1 ) ),
      $_week_link->( $req, $actionp, $name, $sow ),
      $_week_link->( $req, $actionp, $name,
                     $sow->clone->add( weeks => 1 ) ),
      $_week_link->( $req, $actionp, $name,
                     $sow->clone->add( weeks => 2 ) ),
      $_week_link->( $req, $actionp, $name,
                     $sow->clone->add( weeks => 3 ) ),
      $_week_link->( $req, $actionp, $name,
                     $sow->clone->add( weeks => 4 ) );
   return;
};

my $_secondary_authenticated_links = sub {
   my ($self, $req, $nav, $js, $location) = @_;

   p_item $nav, $nav_linkto->( $req, {
      class => 'windows', name => 'profile-user',
      tip   => 'Update personal details', value => 'Profile', }, '#' );

   my $href  = uri_for_action $req, 'user/profile';
   my $title = locm $req, 'Person Profile';

   push @{ $js }, dialog_anchor( 'profile-user', $href, {
      name => 'profile-user', title => $title, useIcon => \1 } );

   my $class = $location eq 'totp_secret' ? 'current' : NUL;

   $req->session->enable_2fa and p_item $nav, $nav_linkto->( $req, {
      class => $class, tip => 'View the TOTP account information',
      value => 'TOTP', }, 'user/totp_secret' );

   $href = uri_for_action $req, 'user/logout_action';

   my $form = blank_form  'authentication', $href, { class => 'none' };

   p_button $form, 'logout-user', 'logout', {
      class => 'none',
      label => locm( $req, 'Logout' ).' ('.$req->session->user_label.')',
      tip   => make_tip $req, 'Logout from [_1]', [ $self->config->title ] };

   p_item $nav, $form;
   return;
};

my $_secondary_unauthenticated_links = sub {
   my ($self, $req, $nav, $js) = @_;

   p_item $nav, $nav_linkto->( $req, {
      class => 'windows', name => 'totp-request',
      tip   => 'Request viewing of the TOTP account information',
      value => 'TOTP', }, '#' );

   my $href  = uri_for_action $req, 'user/totp_request';
   my $title = locm $req, 'TOTP Information Request';

   push @{ $js }, dialog_anchor( 'totp-request', $href, {
      name => 'totp-request', title => $title, useIcon => \1 } );

   p_item $nav, $nav_linkto->( $req, {
      class => 'windows', name => 'request-reset',
      tip   => 'Follow the link to reset your password',
      value => 'Forgot Password?', }, '#' );

   $href  = uri_for_action $req, 'user/reset';
   $title = locm $req, 'Reset Password';

   push @{ $js }, dialog_anchor( 'request-reset', $href, {
      name => 'request-reset', title => $title, useIcon => \1 } );
   return;
};

# Public methods
sub admin_navigation_links {
   my ($self, $req, $page) = @_; $page->{selected} //= NUL;

   my $nav  = $self->navigation_links( $req, $page );
   my $list = $nav->{menu}->{list} //= [];
   my $now  = DateTime->now;

   push @{ $list },
      $nav_folder->( $req, 'events' ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'current_events' ? 'selected' : NUL,
         name => 'current_events' }, 'event/events', [],
                     after  => $now->clone->subtract( days => 1 )->ymd ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'previous_events' ? 'selected' : NUL,
         name => 'previous_events' }, 'event/events', [], before => $now->ymd );

   $self->$_admin_people_links( $req, $page, $nav );

   $self->$_allowed( $req, 'admin/types' ) and push @{ $list },
      $nav_folder->( $req, 'types' ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'types_list' ? 'selected' : NUL,
         name => 'types_list' }, 'admin/types', [] ),
      $nav_linkto->( $req, {
         class => $page->{selected} eq 'slot_roles_list' ? 'selected' : NUL,
         name => 'slot_roles_list' }, 'admin/slot_roles', [] );

   $self->$_allowed( $req, 'asset/vehicles' )
      and $self->$_admin_vehicle_links( $req, $page, $nav );

   return $nav;
}

sub application_logo {
   my ($self, $req) = @_;

   my $conf = $self->config;
   my $logo = $conf->logo;
   my $places = $conf->places;
   my $href = $req->uri_for( $conf->images.'/'.$logo->[ 0 ] );
   my $image = p_image {}, $conf->title.' Logo', $href, {
      height => $logo->[ 2 ], width => $logo->[ 1 ] };
   my $opts = { request => $req, args => [ $conf->title ], value => $image };

   return f_link 'logo', uri_for_action( $req, $places->{logo} ), $opts;
}

sub navigation_links {
   my ($self, $req, $page) = @_; my $nav = {};

   $nav->{logo} = $self->application_logo( $req );
   $nav->{primary} = $self->primary_navigation_links( $req, $page );
   $nav->{secondary} = $self->secondary_navigation_links( $req, $page );

   return $nav;
}

sub primary_navigation_links {
   my ($self, $req, $page) = @_;

   my $nav = blank_form { type => 'unordered' };
   my $location = $page->{location} // NUL;
   my $class = $location eq 'documentation' ? 'current' : NUL;
   my $places = $self->config->places;

   p_item $nav, $nav_linkto->( $req, {
      class => $class, tip => 'Documentation pages for the application',
      value => 'Documentation', }, 'docs/index' );

   $class = $location eq 'posts' ? 'current' : NUL;

   p_item $nav, $nav_linkto->( $req, {
      class => $class, tip => 'Posts about upcoming events',
      value => 'Posts', }, 'posts/index' );

   $class = $location eq 'schedule' ? 'current' : NUL;

   p_item $nav, $nav_linkto->( $req, {
      class => $class, tip => 'Scheduled rotas',
      value => 'Rota', }, $places->{rota} );

   $class = $location eq 'admin' ? 'current' : NUL;

   my $after = DateTime->now->subtract( days => 1 )->ymd;
   my $index = $places->{admin_index};

   $req->authenticated and
      p_item $nav, $nav_linkto->( $req, {
         class => $class, tip => 'admin_index_title',
         value => 'admin_index_link', }, $index, [], after => $after );

   return $nav;
}

sub rota_navigation_links {
   my ($self, $req, $page, $period, $name) = @_;

   my $nav      = $self->navigation_links( $req, $page );
   my $list     = $nav->{menu}->{list} //= [];
   my $actionp  = "${period}/${period}_rota";
   my $date     = $req->session->rota_date // time2str '%Y-%m-01';
   my $local_dt = to_dt( $date )->set_time_zone( 'local' );
   my $f_dom    = $local_dt->clone->set( day => 1 );

   $req->session->rota_date or $self->update_navigation_date( $req, $local_dt );

   push @{ $list }, $nav_folder->( $req, 'year' ),;
   $date = $f_dom->clone->subtract( years => 1 );
   push @{ $list }, $_year_link->( $req, $actionp, $name, $date );
   $date = $f_dom->clone->add( years => 1 );
   push @{ $list }, $_year_link->( $req, $actionp, $name, $date );

   $self->$_rota_month_links( $req, $actionp, $name, $f_dom, $local_dt, $nav );

   my $sow = $local_dt->clone;

   while ($sow->day_of_week > 1) { $sow = $sow->subtract( days => 1 ) }

   $self->$_rota_week_links( $req, $name, $sow, $nav );

   $self->$_allowed( $req, 'week/allocation' ) and push @{ $list },
      $nav_folder->( $req, 'vehicle_allocation' ),
      $_week_link->( $req, 'week/allocation', $name, $sow, {
         value => 'spreadsheet' } );

   return $nav;
}

sub secondary_navigation_links {
   my ($self, $req, $page) = @_;

   my $nav = blank_form { type => 'unordered' };
   my $location = $page->{location} // NUL;
   my $class = $location eq 'login' ? 'current' : NUL;
   my $places = $self->config->places;
   my $js = $page->{literal_js} //= [];

   $req->authenticated or p_item $nav, $nav_linkto->( $req, {
      class => $class, tip => 'Login to the application',
      value => 'Login', }, $places->{login} );

   $class = $location eq 'change_password' ? 'current' : NUL;

   p_item $nav, $nav_linkto->( $req, {
      class => $class,
      tip   => 'Change the password used to access the application',
      value => 'Change Password', }, $places->{password} );

   if ($req->authenticated) {
      $self->$_secondary_authenticated_links( $req, $nav, $js, $location );
   }
   else { $self->$_secondary_unauthenticated_links( $req, $nav, $js ) }

   return $nav;
}

sub update_navigation_date {
   my ($self, $req, $date) = @_; return $req->session->rota_date( $date->ymd );
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
