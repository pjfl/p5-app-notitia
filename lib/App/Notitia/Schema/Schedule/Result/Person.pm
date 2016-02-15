package App::Notitia::Schema::Schedule::Result::Person;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia;
use App::Notitia::Constants    qw( EXCEPTION_CLASS TRUE FALSE NUL );
use App::Notitia::Util         qw( bool_data_type get_salt
                                   nullable_foreign_key_data_type
                                   serial_data_type varchar_data_type );
use Class::Usul::Functions     qw( create_token throw );
use Crypt::Eksblowfish::Bcrypt qw( bcrypt en_base64 );
use HTTP::Status               qw( HTTP_UNAUTHORIZED );
use Try::Tiny;
use Unexpected::Functions      qw( AccountInactive IncorrectPassword );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'person' );

$class->add_columns
   ( id               => serial_data_type,
     next_of_kin      => nullable_foreign_key_data_type,
     active           => bool_data_type,
     password_expired => bool_data_type( TRUE ),
     dob              => { data_type => 'datetime' },
     joined           => { data_type => 'datetime' },
     resigned         => { data_type => 'datetime' },
     subscription     => { data_type => 'datetime' },
     name             => varchar_data_type(  64 ),
     password         => varchar_data_type( 128 ),
     first_name       => varchar_data_type(  64 ),
     last_name        => varchar_data_type(  64 ),
     address          => varchar_data_type(  64 ),
     postcode         => varchar_data_type(  16 ),
     email_address    => varchar_data_type(  64 ),
     mobile_phone     => varchar_data_type(  64 ),
     home_phone       => varchar_data_type(  64 ),
     notes            => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'name' ] );

$class->belongs_to( next_of_kin    => "${class}" );
$class->has_many  ( certifications => "${result}::Certification", 'recipient' );
$class->has_many  ( endorsements   => "${result}::Endorsement",   'recipient' );
$class->has_many  ( roles          => "${result}::Role",          'member'    );
$class->has_many  ( vehicles       => "${result}::Vehicle",       'owner'     );

# Private functions
my $_new_salt = sub {
   my ($type, $lf) = @_;

   return "\$${type}\$${lf}\$"
        . (en_base64( pack( 'H*', substr( create_token, 0, 32 ) ) ) );
};

my $_is_encrypted = sub {
   return $_[ 0 ] =~ m{ \A \$\d+[a]?\$ }mx ? TRUE : FALSE;
};

# Private methods
sub _as_string {
   return $_[ 0 ]->name;
}

my $_assert_membership_allowed = sub {
   my ($self, $type) = @_;

   $type eq 'bike_rider' and $self->assert_certification_for( 'catagory_b' );

   return;
};

my $_encrypt_password = sub {
   my ($self, $name, $password, $stored) = @_;

   my $lf   = $self->result_source->schema->config->load_factor;
   my $salt = defined $stored ? get_salt( $stored ) : $_new_salt->( '2a', $lf );

   return bcrypt( $password, $salt );
};

my $_find_type_by = sub {
   my ($self, $name, $type) = @_;

   return $self->result_source->schema->resultset( 'Type' )->search
      ( { name => $name, type => $type } )->single;
};

my $_find_cert_type = sub {
   return $_[ 0 ]->$_find_type_by( $_[ 1 ], 'certification' );
};

my $_find_role_type = sub {
   return $_[ 0 ]->$_find_type_by( $_[ 1 ], 'role' );
};

# Public methods
sub activate {
   my $self = shift; $self->active( TRUE ); return $self->update;
}

sub add_certification_for {
   my ($self, $cert_name, $opts) = @_; $opts //= {};

   my $type = $self->$_find_cert_type( $cert_name ); my $failed = FALSE;

   try   { $self->assert_certification_for( $cert_name, $type ) }
   catch { $failed = TRUE };

   $failed or throw 'Person [_1] already has certification [_2]',
                    [ $self->name, $type ];

   # TODO: Add the optional completed and notes fields
   return $self->certifications->create
      ( { recipient => $self->id, type => $type->id } );
}

sub add_member_to {
   my ($self, $role_name) = @_;

   my $type = $self->$_find_role_type( $role_name ); my $failed = FALSE;

   try   { $self->assert_member_of( $role_name, $type ) }
   catch { $failed = TRUE };

   $failed or throw 'Person [_1] already a member of role [_2]',
                    [ $self->name, $type ];

   $self->$_assert_membership_allowed( $type );

   return $self->roles->create( { member => $self->id, type => $type->id } );
}

sub assert_certification_for {
   my ($self, $cert_name, $type) = @_;

   $type //= $self->$_find_cert_type( $cert_name );

   my $cert = $self->certifications->find( $self->id, $type->id )
      or throw 'Person [_1] has no certification for [_2]',
               [ $self->name, $type ];

   return $cert;
}

sub assert_member_of {
   my ($self, $role_name, $type) = @_;

   $type //= $self->$_find_role_type( $role_name );

   my $role = $self->roles->find( $self->id, $type->id )
      or throw 'Person [_1] not member of role [_2]', [ $self->name, $type ];

   return $role;
}

sub authenticate {
   my ($self, $passwd, $for_update) = @_;

   $self->active or $for_update
      or throw AccountInactive, [ $self->name ], rv => HTTP_UNAUTHORIZED;

   my $name     = $self->name;
   my $stored   = $self->password || NUL;
   my $supplied = $self->$_encrypt_password( $name, $passwd, $stored );

   $supplied eq $stored
      or throw IncorrectPassword, [ $name ], rv => HTTP_UNAUTHORIZED;
   return;
}

sub deactivate {
   my $self = shift; $self->active( FALSE ); return $self->update;
}

sub delete_certification_for {
   return $_[ 0 ]->assert_certification_for( $_[ 1 ] )->delete;
}

sub delete_member_from {
   my ($self, $role_name) = @_;

   my $role = $self->assert_member_of( $role_name );

   # TODO: Prevent deleting of last role

   return $role->delete;
}

sub insert {
   my $self     = shift;
   my $columns  = { $self->get_inflated_columns };
   my $password = $columns->{password};
   my $name     = $columns->{name};

   $password and not $_is_encrypted->( $password ) and $columns->{password}
      = $self->$_encrypt_password( $name, $password );
   $self->set_inflated_columns( $columns );

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   return $self->next::method;
}

sub list_roles {
   my $self = shift;

   return [ map { $_->type->name }
            $self->roles->search( { member => $self->id } )->all ];
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints    => {
         name        => { max_length => 64, min_length => 3, } },
      fields         => {
         password    => { validate => 'isMandatory' },
         name        => {
            validate => 'isMandatory isValidIdentifier isValidLength' }, },
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Person - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Person;
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
