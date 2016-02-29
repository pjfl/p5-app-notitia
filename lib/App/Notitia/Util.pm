package App::Notitia::Util;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Constants    qw( FALSE NUL SPC TILDE TRUE VARCHAR_MAX_SIZE );
use Class::Usul::Functions     qw( class2appdir create_token find_apphome
                                   get_cfgfiles is_arrayref is_hashref
                                   is_member );
use Class::Usul::Time          qw( str2time time2str );
use Crypt::Eksblowfish::Bcrypt qw( en_base64 );
use Scalar::Util               qw( blessed weaken );

our @EXPORT_OK = qw( admin_navigation_links bind bool_data_type
                     date_data_type delete_button enumerated_data_type enhance
                     foreign_key_data_type get_hashed_pw get_salt is_encrypted
                     loc new_salt nullable_foreign_key_data_type
                     nullable_varchar_data_type numerical_id_data_type
                     save_button serial_data_type set_element_focus
                     set_on_create_datetime_data_type register_action_paths
                     stash_functions uri_for_action varchar_data_type );

# Private class attributes
my $_translations  = {};
# Key is an action path, value a partial URI
my $_action_path_uri_map = {};

# Private functions
my $_action_path2uri = sub {

   my $uri = $_action_path_uri_map->{ $_[ 0 ] } // 'action_path_undefined';

   return $uri;
};

my $_bind_option = sub {
   my ($v, $opts) = @_;

   my $prefix = $opts->{prefix} // NUL;
   my $numify = $opts->{numify} // FALSE;

   return is_arrayref $v
        ? { label =>  $v->[ 0 ].NUL,
            value => ($v->[ 1 ] ? ($numify ? 0 + $v->[ 1 ] : $prefix.$v->[ 1 ])
                                : undef),
            %{ $v->[ 2 ] // {} } }
        : { label => "${v}", value => ($numify ? 0 + $v : $prefix.$v) };
};

my $_nav_folder = sub {
   return { depth => $_[ 2 ] // 0,
            title => loc( $_[ 0 ], $_[ 1 ].'_management_heading' ),
            type  => 'folder', };
};

my $_nav_link = sub {
   return { depth => $_[ 3 ] // 1,
            tip   => loc( $_[ 0 ], $_[ 2 ].'_tip' ),
            title => loc( $_[ 0 ], $_[ 2 ].'_link' ),
            type  => 'link',
            url   => uri_for_action( $_[ 0 ], $_[ 1 ] ), };
};

# Public functions
sub admin_navigation_links ($) {
   my $req = shift;

   return [ $_nav_folder->( $req, 'events' ),
            $_nav_link->( $req, 'event/event', 'event_create' ),
            $_nav_link->( $req, 'event/events', 'events_list' ),
            $_nav_folder->( $req, 'people' ),
            $_nav_link->( $req, 'admin/person', 'person_create' ),
            $_nav_link->( $req, 'admin/people', 'people_list' ),
            $_nav_folder->( $req, 'vehicles' ),
            $_nav_link->( $req, 'admin/vehicle', 'vehicle_create' ),
            $_nav_link->( $req, 'admin/vehicles', 'vehicles_list' ), ];
}

sub bind {
   my ($name, $v, $opts) = @_; $opts //= {};

   my $numify = $opts->{numify} // FALSE;
   my $params = { label => $name, name => $name }; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $params->{value} = $v->ymd;
   }
   elsif (is_arrayref $v) {
      $params->{value} = [ map { $_bind_option->( $_, $opts ) } @{ $v } ];
   }
   else { defined $v and $params->{value} = $numify ? 0 + $v : "${v}" }

   delete $opts->{numify}; delete $opts->{prefix};

   $params->{ $_ } = $opts->{ $_ } for (keys %{ $opts });

   return $params;
}

sub bool_data_type (;$) {
   return { data_type     => 'boolean',
            default_value => $_[ 0 ] // FALSE,
            is_nullable   => FALSE, };
}

sub date_data_type () {
   return { data_type     => 'datetime',
            default_value => '0000-00-00',
            is_nullable   => TRUE,
            datetime_undef_if_invalid => TRUE, }
}

sub delete_button ($$;$) {
   my ($req, $name, $type) = @_;

   my $button = { container_class => 'right', label => 'delete',
                  value           => "delete_${type}" };

   $type and $button->{tip} = loc( $req, 'Hint' ).SPC.TILDE.SPC
                            . loc( $req, 'delete_tip', [ $type, $name ] );

   return $button;
};

sub enumerated_data_type ($;$) {
   return { data_type     => 'enum',
            default_value => $_[ 1 ],
            extra         => { list => $_[ 0 ] },
            is_enum       => TRUE, };
}

sub enhance ($) {
   my $conf = shift;
   my $attr = { config => { %{ $conf } }, }; $conf = $attr->{config};

   $conf->{appclass    } //= 'App::Notitia';
   $attr->{config_class} //= $conf->{appclass}.'::Config';
   $conf->{name        } //= class2appdir $conf->{appclass};
   $conf->{home        } //= find_apphome $conf->{appclass}, $conf->{home};
   $conf->{cfgfiles    } //= get_cfgfiles $conf->{appclass}, $conf->{home};

   return $attr;
}

sub foreign_key_data_type (;$$) {
   my $type_info = { data_type     => 'integer',
                     default_value => $_[ 0 ],
                     extra         => { unsigned => TRUE },
                     is_nullable   => FALSE,
                     is_numeric    => TRUE, };

   defined $_[ 1 ] and $type_info->{accessor} = $_[ 1 ];

   return $type_info;
}

sub get_hashed_pw ($) {
   my @parts = split m{ [\$] }mx, $_[ 0 ]; return substr $parts[ -1 ], 22;
}

sub get_salt ($) {
   my @parts = split m{ [\$] }mx, $_[ 0 ];

   $parts[ -1 ] = substr $parts[ -1 ], 0, 22;

   return join '$', @parts;
}

sub is_encrypted ($) {
   return $_[ 0 ] =~ m{ \A \$\d+[a]?\$ }mx ? TRUE : FALSE;
}

sub loc ($$;@) {
   my ($req, $k, @args) = @_;

   $_translations->{ my $locale = $req->locale } //= {};

   return exists $_translations->{ $locale }->{ $k }
               ? $_translations->{ $locale }->{ $k }
               : $_translations->{ $locale }->{ $k } = $req->loc( $k, @args );
}

sub new_salt ($$) {
   my ($type, $lf) = @_;

   return "\$${type}\$${lf}\$"
        . (en_base64( pack( 'H*', substr( create_token, 0, 32 ) ) ) );
}

sub nullable_foreign_key_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_nullable       => TRUE,
            is_numeric        => TRUE, };
}

sub nullable_varchar_data_type (;$$) {
   return { data_type         => 'varchar',
            default_value     => $_[ 1 ],
            is_nullable       => TRUE,
            size              => $_[ 0 ] || VARCHAR_MAX_SIZE, };
}

sub numerical_id_data_type (;$) {
   return { data_type         => 'smallint',
            default_value     => $_[ 0 ],
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub register_action_paths (;@) {
   my $args = (is_hashref $_[ 0 ]) ? $_[ 0 ] : { @_ };

   for my $k (keys %{ $args }) {
      $_action_path_uri_map->{ $k } = $args->{ $k };
   }

   return;
}

sub save_button ($$;$) {
   my ($req, $name, $type) = @_; my $k = $name ? 'update' : 'create';

   my $button = { container_class => 'right', label => $k,
                  value           => "${k}_${type}" };

   $type and $button->{tip} = loc( $req, 'Hint' ).SPC.TILDE.SPC
                            . loc( $req, "${k}_tip", [ $type, $name ] );

   return $button;
}

sub serial_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_auto_increment => TRUE,
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub set_element_focus ($$) {
   my ($form, $name) = @_;

   return [ "var form = document.forms[ '${form}' ];",
            "var f = function() { behaviour.rebuild(); form.${name}.focus() };",
            'f.delay( 100 );', ];
}

sub set_on_create_datetime_data_type () {
   return { %{ date_data_type() }, set_on_create => TRUE };
}

sub stash_functions ($$$) {
   my ($app, $req, $dest) = @_; weaken $req;

   $dest->{is_member     } = \&is_member;
   $dest->{loc           } = sub { loc( $req, $_[ 0 ] ) };
   $dest->{reference     } = sub { ref $_[ 0 ] };
   $dest->{str2time      } = \&str2time;
   $dest->{time2str      } = \&time2str;
   $dest->{ucfirst       } = sub { ucfirst $_[ 0 ] };
   $dest->{uri_for       } = sub { $req->uri_for( @_ ), };
   $dest->{uri_for_action} = sub { uri_for_action( $req, @_ ), };
   return;
}

sub uri_for_action ($$;@) {
   my ($req, $action, @args) = @_;

   return $req->uri_for( $_action_path2uri->( $action ), @args );
}

sub varchar_data_type (;$$) {
   return { data_type         => 'varchar',
            default_value     => $_[ 1 ] // NUL,
            is_nullable       => FALSE,
            size              => $_[ 0 ] || VARCHAR_MAX_SIZE, };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Util - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Util;
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
