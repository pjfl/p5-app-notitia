package App::Notitia::Util;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Constants    qw( FALSE NUL TRUE VARCHAR_MAX_SIZE );
use Class::Usul::Functions     qw( class2appdir create_token find_apphome
                                   get_cfgfiles is_member );
use Class::Usul::Time          qw( str2time time2str );
use Crypt::Eksblowfish::Bcrypt qw( en_base64 );
use Scalar::Util               qw( weaken );

our @EXPORT_OK = qw( bool_data_type date_data_type enumerated_data_type enhance
                     foreign_key_data_type get_hashed_pw get_salt
                     is_encrypted new_salt nullable_foreign_key_data_type
                     nullable_varchar_data_type numerical_id_data_type
                     serial_data_type set_on_create_datetime_data_type
                     stash_functions varchar_data_type );

# Public functions
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
   $attr->{config_class} //= $conf->{appclass}.'::Notitia';
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

sub serial_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_auto_increment => TRUE,
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub set_on_create_datetime_data_type () {
   return { data_type         => 'datetime',
            set_on_create     => TRUE, };
}

sub stash_functions ($$$) {
   my ($app, $src, $dest) = @_; weaken $src;

   $dest->{is_member} = \&is_member;
   $dest->{loc      } = sub { $src->loc( @_ ) };
   $dest->{str2time } = \&str2time;
   $dest->{time2str } = \&time2str;
   $dest->{ucfirst  } = sub { ucfirst $_[ 0 ] };
   $dest->{uri_for  } = sub { $src->uri_for( @_ ), };
   return;
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
