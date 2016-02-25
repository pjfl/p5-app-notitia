package App::Notitia::Schema::Schedule::Result::Person;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia;
use App::Notitia::Constants    qw( EXCEPTION_CLASS TRUE
                                   FALSE NUL VARCHAR_MAX_SIZE );
use App::Notitia::Util         qw( bool_data_type date_data_type get_salt
                                   is_encrypted new_salt
                                   nullable_foreign_key_data_type
                                   serial_data_type varchar_data_type );
use Class::Usul::Functions     qw( throw );
use Crypt::Eksblowfish::Bcrypt qw( bcrypt en_base64 );
use HTTP::Status               qw( HTTP_UNAUTHORIZED );
use Try::Tiny;
use Unexpected::Functions      qw( AccountInactive IncorrectPassword
                                   PasswordExpired SlotTaken );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'person' );

$class->add_columns
   ( id               => serial_data_type,
     next_of_kin      => nullable_foreign_key_data_type,
     active           => bool_data_type,
     password_expired => bool_data_type( TRUE ),
     dob              => date_data_type,
     joined           => date_data_type,
     resigned         => date_data_type,
     subscription     => date_data_type,
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

$class->belongs_to( next_of_kin => "${class}" );

$class->has_many( certs        => "${result}::Certification", 'recipient_id'  );
$class->has_many( endorsements => "${result}::Endorsement",   'recipient_id'  );
$class->has_many( participents => "${result}::Participent",   'participent_id');
$class->has_many( roles        => "${result}::Role",          'member_id'     );
$class->has_many( vehicles     => "${result}::Vehicle",       'owner_id'      );

# Private methods
sub _as_string {
   return $_[ 0 ]->name;
}

my $_assert_claim_allowed = sub {
   my ($self, $slot_type, $bike_wanted) = @_;

   $slot_type eq 'rider' and $self->assert_member_of( 'bike_rider' );
   $slot_type ne 'rider' and $bike_wanted
      and throw 'Cannot request a bike for slot type [_1]', [ $slot_type ];

   return;
};

my $_assert_membership_allowed = sub {
   my ($self, $type) = @_;

   $type eq 'bike_rider' and $self->assert_certified_for( 'catagory_b' );

   return;
};

my $_encrypt_password = sub {
   my ($self, $name, $password, $stored) = @_;

   # Name attribute used by alternative encryption schemes
   my $lf   = $self->result_source->schema->config->load_factor;
   my $salt = defined $stored ? get_salt( $stored ) : new_salt( '2a', $lf );

   return bcrypt( $password, $salt );
};

my $_find_event_by = sub {
   my ($self, $name) = @_;

   return $self->result_source->schema->resultset( 'Event' )->search
      ( { name => $name } )->single;
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

   my $type = $self->$_find_cert_type( $cert_name );

   $self->is_certified_for( $cert_name, $type )
      and throw 'Person [_1] already has certification [_2]', [ $self, $type ];

   # TODO: Add the optional completed and notes fields
   return $self->create_related( 'certs', { type_id => $type->id } );
}

sub add_endorsement_for {
   my ($self, $code_name) = @_;

   $self->is_endorsed_for( $code_name )
      and throw 'Person [_1] already has endorsement for [_2]',
                [ $self, $code_name ];

   # TODO: Add the fields endorsed, points, and notes
   return $self->create_related( 'endorsements', { code => $code_name } );
}

sub add_member_to {
   my ($self, $role_name) = @_;

   my $type = $self->$_find_role_type( $role_name );

   $self->is_member_of( $role_name, $type )
      and throw 'Person [_1] already a member of role [_2]', [ $self, $type ];

   $self->$_assert_membership_allowed( $type );

   return $self->create_related( 'roles', { type_id => $type->id } );
}

sub add_participent_for {
   my ($self, $event_name) = @_;

   my $event = $self->$_find_event_by( $event_name );

   $self->is_participent_of( $event_name, $event )
      and throw 'Person [_1] already participating in [_2]', [ $self, $event ];

   return $self->create_related( 'participents', { event_id => $event->id } );
}

sub assert_certified_for {
   my ($self, $cert_name, $type) = @_;

   $type //= $self->$_find_cert_type( $cert_name );

   my $cert = $self->certs->find( $self->id, $type->id )
      or throw 'Person [_1] has no certification for [_2]',
               [ $self, $type ], level => 2;

   return $cert;
}

sub assert_endorsement_for {
   my ($self, $code_name) = @_;

   my $endorsement = $self->endorsements->find( $self->id, $code_name )
      or throw 'Person [_1] has no endorsement for [_2]',
               [ $self, $code_name ], level => 2;

   return $endorsement;
}

sub assert_member_of {
   my ($self, $role_name, $type) = @_;

   $type //= $self->$_find_role_type( $role_name );

   my $role = $self->roles->find( $self->id, $type->id )
      or throw 'Person [_1] is not a member of role [_2]',
               [ $self, $type ], level => 2;

   return $role;
}

sub assert_participent_for {
   my ($self, $event_name) = @_;

   my $event       = $self->$_find_event_by( $event_name );
   my $participent = $self->participents->find( $event->id, $self->id )
      or throw 'Person [_1] is not participating in [_2]',
               [ $self, $event ], level => 2;

   return $participent;
}

sub authenticate {
   my ($self, $passwd, $for_update) = @_;

   $self->active
      or  throw AccountInactive,   [ $self ], rv => HTTP_UNAUTHORIZED;

   $self->password_expired and not $for_update
      and throw PasswordExpired,   [ $self ], rv => HTTP_UNAUTHORIZED;

   my $stored   = $self->password || NUL;
   my $supplied = $self->$_encrypt_password( $self->name, $passwd, $stored );

   $supplied eq $stored
      or  throw IncorrectPassword, [ $self ], rv => HTTP_UNAUTHORIZED;

   return;
}

sub claim_slot {
   my ($self, $rota_name, $date, $shift_type, $slot_type, $subslot, $bike) = @_;

   $self->$_assert_claim_allowed( $slot_type, $bike );

   my $shift = $self->find_shift( $rota_name, $date, $shift_type );
   my $slot  = $self->find_slot( $shift, $slot_type, $subslot );

   $slot and throw SlotTaken, [ $slot, $slot->operator ];

   return $self->result_source->schema->resultset( 'Slot' )->create
      ( { bike_requested => $bike,      operator_id => $self->id,
          shift_id       => $shift->id, subslot     => $subslot,
          type           => $slot_type, } );
}

sub deactivate {
   my $self = shift; $self->active( FALSE ); return $self->update;
}

sub delete_certification_for {
   return $_[ 0 ]->assert_certified_for( $_[ 1 ] )->delete;
}

sub delete_endorsement_for {
   return $_[ 0 ]->assert_endorsement_for( $_[ 1 ] )->delete;
}

sub delete_member_from {
   my ($self, $role_name) = @_;

   my $role = $self->assert_member_of( $role_name );

   # TODO: Prevent deleting of last role

   return $role->delete;
}

sub delete_participent_for {
   return $_[ 0 ]->assert_participent_for( $_[ 1 ] )->delete;
}

sub insert {
   my $self     = shift;
   my $columns  = { $self->get_inflated_columns };
   my $password = $columns->{password};
   my $name     = $columns->{name};

   $password and not is_encrypted( $password ) and $columns->{password}
      = $self->$_encrypt_password( $name, $password );
   $self->set_inflated_columns( $columns );

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   return $self->next::method;
}

sub is_certified_for {
   my ($self, $cert_name, $type) = @_;

   $type //= $self->$_find_cert_type( $cert_name );

   return $type && $self->certs->find( $self->id, $type->id ) ? TRUE : FALSE;
}

sub is_endorsed_for {
   return $_[ 1 ] && $_[ 0 ]->endorsements->find( $_[ 0 ]->id, $_[ 1 ] )
        ? TRUE : FALSE;
}

sub is_member_of {
   my ($self, $role_name, $type) = @_;

   $type //= $self->$_find_role_type( $role_name );

   return $type && $self->roles->find( $self->id, $type->id ) ? TRUE : FALSE;
}

sub is_participent_of {
   my ($self, $event_name, $event) = @_;

   $event //= $self->$_find_event_by( $event_name );

   return $event && $self->participents->find( $event->id, $self->id )
        ? TRUE : FALSE;
}

sub list_roles {
   my $self = shift;

   return [ map { $_->type->name }
            $self->roles->search( {}, { prefetch => 'type' } )->all ];
}

sub set_password {
   my ($self, $old, $new) = @_;

   $self->authenticate( $old, TRUE );
   $self->password( $new );
   $self->password_expired( FALSE );

   return $self->update;
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $columns = { $self->get_inflated_columns };

   my $name = $columns->{name}; my $password = $columns->{password};

   $password and not is_encrypted( $password ) and $columns->{password}
      = $self->$_encrypt_password( $name, $password );

   $self->set_inflated_columns( $columns ); $self->validate;

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints      => {
         address       => { max_length =>  64, min_length => 0, },
         email_address => { max_length =>  64, min_length => 0, },
         first_name    => { max_length =>  64, min_length => 1, },
         last_name     => { max_length =>  64, min_length => 1, },
         name          => { max_length =>  64, min_length => 3, },
         notes         => { max_length =>  VARCHAR_MAX_SIZE(),
                            min_length =>   0, },
         password      => { max_length => 128, min_length => 8, },
         postcode      => { max_length =>  16, min_length => 0, },
      },
      fields           => {
         address       => { validate => 'isValidLength isPrintable' },
         dob           => { validate => 'isValidDate' },
         email_address => {
            validate   => 'isMandatory isValidLength isValidEmail' },
         first_name    => {
            validate   => 'isMandatory isValidLength isPrintable' },
         home_phone    => { filters  => 'filterNonNumeric',
                            validate => 'isValidInteger' },
         joined        => { validate => 'isValidDate' },
         last_name     => {
            validate   => 'isMandatory isValidLength isPrintable' },
         mobile_phone  => { filters  => 'filterNonNumeric',
                            validate => 'isValidInteger' },
         name          => {
            validate   => 'isMandatory isValidLength isValidIdentifier' },
         notes         => { validate => 'isValidLength isPrintable' },
         password      => {
            validate   => 'isMandatory isValidLength isValidPassword' },
         postcode      => { validate => 'isValidLength isValidPostcode' },
         resigned      => { validate => 'isValidDate' },
         subscription  => { validate => 'isValidDate' },
      },
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
