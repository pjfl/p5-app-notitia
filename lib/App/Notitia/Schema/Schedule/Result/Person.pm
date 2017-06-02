package App::Notitia::Schema::Schedule::Result::Person;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string },
             '+'  => sub { $_[ 0 ]->_as_number }, fallback => 1;
use parent   'App::Notitia::Schema::Schedule::Base::Result';

use App::Notitia;
use App::Notitia::Constants    qw( EXCEPTION_CLASS SPC TRUE
                                   FALSE NUL SHIFT_TYPE_ENUM VARCHAR_MAX_SIZE );
use App::Notitia::DataTypes    qw( bool_data_type date_data_type
                                   nullable_foreign_key_data_type
                                   nullable_numerical_id_data_type
                                   numerical_id_data_type
                                   serial_data_type varchar_data_type );
use App::Notitia::Util         qw( get_salt is_encrypted local_dt new_salt
                                   now_dt slot_limit_index );
use Auth::GoogleAuth;
use Class::Usul::Functions     qw( create_token64 first_char is_member throw );
use Crypt::Eksblowfish::Bcrypt qw( bcrypt en_base64 );
use List::SomeUtils            qw( first_index );
use Try::Tiny;
use Unexpected::Functions      qw( AccountInactive FailedSecurityCheck
                                   IncorrectAuthCode IncorrectPassword
                                   PasswordExpired SlotFree SlotTaken
                                   Unspecified );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'person' );

$class->add_columns
   ( id               => serial_data_type,
     next_of_kin_id   => nullable_foreign_key_data_type,
     active           => bool_data_type,
     password_expired => bool_data_type( TRUE ),
     badge_expires    => date_data_type,
     dob              => date_data_type,
     joined           => date_data_type,
     resigned         => date_data_type,
     subscription     => date_data_type,
     badge_id         => nullable_numerical_id_data_type,
     rows_per_page    => numerical_id_data_type( 20 ),
     shortcode        => varchar_data_type(   8 ),
     name             => varchar_data_type(  64 ),
     password         => varchar_data_type( 128 ),
     first_name       => varchar_data_type(  32 ),
     last_name        => varchar_data_type(  32 ),
     address          => varchar_data_type(  64 ),
     postcode         => varchar_data_type(  16 ),
     location         => varchar_data_type(  24 ),
     coordinates      => varchar_data_type(  16 ),
     email_address    => varchar_data_type(  64 ),
     mobile_phone     => varchar_data_type(  16 ),
     home_phone       => varchar_data_type(  16 ),
     totp_secret      => varchar_data_type(  16 ),
     region           => varchar_data_type(   1 ),
     notes            => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'badge_id' ] );
$class->add_unique_constraint( [ 'name' ] );
$class->add_unique_constraint( [ 'email_address' ] );
$class->add_unique_constraint( [ 'shortcode' ] );

$class->belongs_to( next_of_kin => "${class}", 'next_of_kin_id', $left_join );

$class->has_many( certs        => "${result}::Certification", 'recipient_id'  );
$class->has_many( courses      => "${result}::Training",      'recipient_id'  );
$class->has_many( deactivated  => "${result}::Unsubscribe",   'recipient_id'  );
$class->has_many( endorsements => "${result}::Endorsement",   'recipient_id'  );
$class->has_many( participents => "${result}::Participent",   'participent_id');
$class->has_many( roles        => "${result}::Role",          'member_id'     );
$class->has_many( slots        => "${result}::Slot",          'operator_id'   );
$class->has_many( vehicles     => "${result}::Vehicle",       'owner_id'      );

# Private methods
sub _as_number {
   return $_[ 0 ]->id;
}

sub _as_string {
   return $_[ 0 ]->shortcode;
}

my $_list_slot_certs_for = sub {
   my ($self, $slot_type) = @_;

   my $schema = $self->result_source->schema;
   my $rs     = $schema->resultset( 'SlotCriteria' );
   my $where  = { 'slot_type' => $slot_type };
   my $opts   = { prefetch => 'certification_type' };

   return [ map { $_->certification_type } $rs->search( $where, $opts )->all ];
};

my $_assert_yield_allowed = sub {
   my ($self, $slot) = @_;

   $self->is_member_of( 'rota_manager' ) or $self->id == $slot->operator_id
      or throw 'Yield slot - permission denied';

   return;
};

my $_encrypt_password = sub {
   my ($self, $shortcode, $password, $stored) = @_;

   # Shortcode attribute used by alternative encryption schemes
   my $lf   = $self->result_source->schema->config->load_factor;
   my $salt = defined $stored ? get_salt( $stored ) : new_salt( '2a', $lf );

   return bcrypt( $password, $salt );
};

my $_find_cert_type = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_certification_by( $name );
};

my $_find_course_type = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_course_by( $name );
};

my $_find_role_type = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_role_by( $name );
};

my $_find_rota_type = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_rota_by( $name );
};

my $_new_shortcode = sub {
   my ($self, $first_name, $last_name) = @_; my $cache = {}; my $lid;

   my $schema = $self->result_source->schema; my $conf = $schema->config;

   my $name = lc "${last_name}${first_name}"; $name =~ s{ [ \-\'] }{}gmx;

   if ((length $name) < $conf->min_name_length) {
      throw 'Person name [_1] too short [_2] character min.',
            [ $first_name.SPC.$last_name, $conf->min_name_length ];
   }

   my $min_id_len = $conf->min_id_length;
   my $prefix     = $conf->person_prefix; $prefix or return;
   my $lastp      = length $name < $min_id_len ? length $name : $min_id_len;
   my @chars      = (); $chars[ $_ ] = $_ for (0 .. $lastp - 1);
   my $person_rs  = $schema->resultset( 'Person' );

   while ($chars[ $lastp - 1 ] < length $name) {
      my $i = 0; $lid = NUL;

      while ($i < $lastp) { $lid .= substr $name, $chars[ $i++ ], 1 }

      $person_rs->is_person( $prefix.$lid, $cache ) or last;

      $i = $lastp - 1; $chars[ $i ] += 1;

      while ($i >= 0 and $chars[ $i ] >= length $name) {
         my $ripple = $i - 1; $chars[ $ripple ] += 1;

         while ($ripple < $lastp) {
            my $carry = $ripple + 1; $chars[ $carry ] = $chars[ $ripple++ ] + 1;
         }

         $i--;
      }
   }

   $chars[ $lastp - 1 ] >= length $name
       and throw 'Person name [_1] no ids left', [ $first_name.SPC.$last_name ];
   $lid or throw 'Person name [_1] no id', [ $name ];
   return $prefix.$lid;
};

my $_assert_no_slot_collision = sub {
   my ($self, $rota_type, $dt, $shift_type, $slot_type) = @_;

   my $rs   = $self->result_source->schema->resultset( 'Slot' );
   my $opts = { rota_type => $rota_type->id, on => $dt };

   for my $slot ($rs->search_for_slots( $opts )->all) {
      $slot->shift eq $shift_type and $self->id == $slot->operator->id
         and not ($slot_type eq 'controller' and $slot_type eq $slot->type_name)
         and throw 'Person already assigned to slot [_1]', [ $slot ];
   }

   return;
};

my $_assert_not_too_many_slots = sub {
   my ($self, $rota_type, $rota_dt) = @_;

   my $app = $self->result_source->schema->application;
   my $max_slots = $app->config->max_slots;
   my $opts = { after => $rota_dt->clone->subtract( days => $max_slots + 1 ),
                before => $rota_dt->clone->add( days => $max_slots + 1 ),
                operator => $self->shortcode,
                order_by => [ 'rota.date', 'shift.type_name' ],
                rota_type => $rota_type->id };
   my $rs = $self->result_source->schema->resultset( 'Slot' );
   my %taken = ();

   for my $slot ($rs->search_for_slots( $opts )->all) {
      $taken{ int $slot->start_date->jd } = $slot->start_date->ymd;
   }

   exists $taken{ int $rota_dt->jd } and return;

   my $prev_jd; my $remaining = $max_slots - 1;

   for my $jd (sort keys %taken) {
      if ($prev_jd and $jd == $prev_jd + 1) { $remaining-- }
      else { $remaining = $max_slots - 1 }

      $prev_jd = $jd;
   }

   $remaining < 1
      and throw 'Only [_1] consecutive duty-days are allowed', [ $max_slots ];

   return;
};

my $_assert_claim_allowed = sub {
   my ($self, $rota_name, $rota_dt, $slot_name, $request_sv, $assigner) = @_;

   my $rota_type = $self->$_find_rota_type( $rota_name );

   my ($shift_t, $slot_t, $slotno) = split m{ _ }mx, $slot_name, 3;

   $self->$_assert_no_slot_collision( $rota_type, $rota_dt, $shift_t, $slot_t );

   $self->shortcode eq $assigner
      and $self->$_assert_not_too_many_slots( $rota_type, $rota_dt );

   $slot_t eq 'driver' and $self->assert_member_of( 'driver' );
   $slot_t eq 'rider'  and $self->assert_member_of( 'rider' );
   $slot_t eq 'driver' or $slot_t eq 'rider' or not $request_sv or throw
      'Cannot request a service vehicle for slot type [_1]', [ $slot_t ];

   for my $cert (@{ $self->$_list_slot_certs_for( $slot_t ) }) {
      $self->assert_certified_for( $cert );
   }

   my $conf = $self->result_source->schema->config;
   my $i    = slot_limit_index $shift_t, $slot_t;

   $slotno > $conf->slot_limits->[ $i ] - 1
      and throw 'Cannot claim slot [_1] greater than slot limit [_2]',
          [ $slotno, $conf->slot_limits->[ $i ] - 1 ];

   $slot_t eq 'rider' and now_dt->add( weeks => 4 ) < $rota_dt
      and $self->region ne first_char uc $conf->slot_region->{ $slotno }
      and throw 'Cannot claim slot [_1] out of region', [ $slotno ];

   return;
};

# Public methods
sub activate {
   my $self = shift; $self->active( TRUE ); return $self->update;
}

sub add_course {
   my ($self, $course_name) = @_;

   my $type = $self->$_find_course_type( $course_name );

   $self->is_enrolled_on( $course_name, $type )
      and throw '[_1] already enrolled on [_2]', [ $self->label, $type ];

   return $self->create_related( 'courses', {
      course_type_id => $type->id, status => 'enrolled' } );
}

sub add_member_to {
   my ($self, $role_name) = @_;

   my $type = $self->$_find_role_type( $role_name );

   $self->is_member_of( $role_name, $type )
      and throw '[_1] already a member of role [_2]', [ $self->label, $type ];

   return $self->create_related( 'roles', { type_id => $type->id } );
}

sub add_participent_for {
   my ($self, $event_uri) = @_;

   my $event_rs = $self->result_source->schema->resultset( 'Event' );
   my $event    = $event_rs->find_event_by( $event_uri );

   $self->is_participating_in( $event_uri, $event )
      and throw '[_1] already participating in [_2]', [ $self->label, $event ];

   if ($event->max_participents) {
      $event->max_participents > $event->count_of_participents
         or throw 'Maximum number of paticipants reached';
   }

   return $self->create_related( 'participents', { event_id => $event->id } );
}

sub assert_can_email {
   my $self = shift;

   $self->email_address or throw '[_1] has no email address', [ $self->label ];
   $self->can_email
      or throw '[_1] has an example email address', [ $self->label ];

   return;
}

sub assert_certified_for {
   my ($self, $cert_name, $type) = @_;

   $type //= $self->$_find_cert_type( $cert_name );

   my $cert = $self->certs->find( $self->id, $type->id )
      or throw '[_1] has no certification for [_2]',
               [ $self->label, $type ], level => 2;

   return $cert;
}

sub assert_endorsement_for {
   my ($self, $code_name) = @_;

   my $endorsement = $self->endorsements->find( $self->id, $code_name )
      or throw '[_1] has no endorsement for [_2]',
               [ $self->label, $code_name ], level => 2;

   return $endorsement;
}

sub assert_enrolled_on {
   my ($self, $course_name, $type) = @_;

   $type //= $self->$_find_course_type( $course_name );

   my $course = $self->courses->find( $self->id, $type->id )
      or throw '[_1] is not enrolled on a [_2] course',
               [ $self->label, $type ], level => 2;

   return $course;
}

sub assert_member_of {
   my ($self, $role_name, $type) = @_;

   $type //= $self->$_find_role_type( $role_name );

   my $role = $self->roles->find( $self->id, $type->id )
      or throw '[_1] is not a member of the [_2] role',
               [ $self->label, $type ], level => 2;

   return $role;
}

sub assert_participating_in {
   my ($self, $event_uri) = @_;

   my $event_rs    = $self->result_source->schema->resultset( 'Event' );
   my $event       = $event_rs->find_event_by( $event_uri );
   my $participent = $self->participents->find( $event->id, $self->id )
      or throw '[_1] is not participating in the [_2] event',
               [ $self->label, $event ], level => 2;

   return $participent;
}

sub authenticate {
   my ($self, $passwd, $for_update) = @_;

   $self->active or throw AccountInactive, [ $self ];

   $self->password_expired and not $for_update
      and throw PasswordExpired, [ $self ];

   my $shortcode = $self->shortcode;
   my $stored    = $self->password || NUL;
   my $supplied  = $self->$_encrypt_password( $shortcode, $passwd, $stored );

   $supplied eq $stored or throw IncorrectPassword, [ $self ];

   return;
}

sub authenticate_optional_2fa {
   my ($self, $passwd, $auth_code) = @_; $self->authenticate( $passwd );

   not $auth_code and $self->totp_secret and throw Unspecified, [ 'auth code' ];

   $auth_code and not $self->totp_authenticator->verify( $auth_code )
              and throw IncorrectAuthCode, [ $self ];

   return;
}

sub can_email {
   my $self = shift;

   $self->email_address or return FALSE;
   $self->email_address =~ m{ \@example\.com \z }mx and return FALSE;

   return TRUE;
}

sub claim_slot {
   my ($self, $name, $dt, $slot_name, $request_sv, $vehicle, $assigner) = @_;

   $self->$_assert_claim_allowed
      ( $name, $dt, $slot_name, $request_sv, $assigner );

   my ($shift_type, $slot_type, $slotno) = split m{ _ }mx, $slot_name, 3;

   my $shift = $self->find_shift( $name, $dt, $shift_type );
   my $slot  = $self->find_slot( $shift, $slot_type, $slotno );

   $slot and throw SlotTaken, [ $slot, $slot->operator ];

   my $attr = { bike_requested => $request_sv, shift_id => $shift->id,
                subslot        => $slotno, type_name => $slot_type, };

   $vehicle and $attr->{operator_vehicle_id} = $vehicle->id;

   return $self->create_related( 'slots', $attr );
}

sub deactivate {
   my $self = shift; $self->active( FALSE ); return $self->update;
}

sub delete_course {
   return $_[ 0 ]->assert_enrolled_on( $_[ 1 ] )->delete;
}

sub delete_member_from {
   return $_[ 0 ]->assert_member_of( $_[ 1 ] )->delete;
}

sub delete_participent_for {
   return $_[ 0 ]->assert_participating_in( $_[ 1 ] )->delete;
}

sub execute {
   my ($self, $method) = @_;

   is_member $method, [ qw( totp_secret ) ] or return FALSE;

   return $self->$method();
}

sub has_stopped_email {
   my ($self, $action) = @_;

   return $self->find_related
      ( 'deactivated', { sink => 'email', action => $action } ) ? TRUE : FALSE;
}

sub has_stopped_sms {
   my ($self, $action) = @_;

   return $self->find_related
      ( 'deactivated', { sink => 'sms', action => $action } ) ? TRUE : FALSE;
}

sub insert {
   my $self    = shift;
   my $columns = { $self->get_inflated_columns };
   my $first   = lc $columns->{first_name}; $first =~ s{[^a-z]}{}gmx;
   my $last    = lc $columns->{last_name}; $last =~ s{[^a-z]}{}gmx;

   $columns->{name} or $columns->{name} = "${first}.${last}";
   $columns->{email_address} or $columns->{email_address}
      = $columns->{name}.'@example.com';
   $columns->{shortcode} or $columns->{shortcode}
      = $self->$_new_shortcode( $first, $last );
   $self->set_inflated_columns( $columns );

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   $columns = { $self->get_inflated_columns };

   my $password = $columns->{password};

   $password and not is_encrypted( $password ) and $columns->{password}
      = $self->$_encrypt_password( $columns->{shortcode}, $password )
         and $self->set_inflated_columns( $columns );

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

sub is_enrolled_on {
   my ($self, $course_name, $type) = @_;

   $type //= $self->$_find_course_type( $course_name );

   return $type && $self->courses->find( $self->id, $type->id ) ? TRUE : FALSE;
}

sub is_member_of {
   my ($self, $role_name, $type) = @_;

   $type //= $self->$_find_role_type( $role_name );

   return $type && $self->roles->find( $self->id, $type->id ) ? TRUE : FALSE;
}

sub is_participating_in {
   my ($self, $event_uri, $event) = @_;

   $event //= $self->result_source->schema->resultset( 'Event' )
                   ->find_event_by( $event_uri );

   return $event && $self->participents->find( $event->id, $self->id )
        ? TRUE : FALSE;
}

sub label {
   return ucfirst( $_[ 0 ]->first_name ).SPC.ucfirst( $_[ 0 ]->last_name );
}

sub list_courses {
   my $self = shift; my $opts = { prefetch => 'course_type' };

   return [ map { $_->course_type->name }
            $self->courses->search( {}, $opts )->all ];
}

sub list_events {
   my ($self, $opts) = @_; $opts = { %{ $opts // {} } };

   my $parser = $self->result_source->schema->datetime_parser;
   my $after  = delete $opts->{after};
   my $where  = {};

   $after and $where->{ 'start_rota.date' }->{ '>' }
      = $parser->format_datetime( $after );

   $opts->{prefetch} //= { 'event' => 'start_rota' };

   return
      [ map { $_->event } $self->participents->search( $where, $opts )->all ];
}

sub list_roles {
   my $self = shift; my $opts = { order_by => 'type.name', prefetch => 'type' };

   return [ map { $_->type->name } $self->roles->search( {}, $opts )->all ];
}

sub outer_postcode {
   my $self    = shift;
   my ($outer) = split SPC, ($self->postcode // NUL); $outer //= NUL;

   return $outer;
}

sub security_check {
   my ($self, $opts) = @_;

   for my $k (keys %{ $opts }) {
      $opts->{ $k } eq $self->$k() or throw FailedSecurityCheck, [ $self ];
   }

   return;
}

sub set_password {
   my ($self, $old, $new) = @_;

   $self->authenticate( $old, TRUE );
   $self->password( $new );
   $self->password_expired( FALSE );

   return $self->update;
}

sub set_totp_secret {
   my ($self, $enable) = @_; my $current = $self->totp_secret ? TRUE : FALSE;

   $enable  and not $current
      and return $self->totp_secret( substr create_token64, 0, 16 );
   $current and not $enable and return $self->totp_secret( NUL );

   return $self->totp_secret;
}

sub subscribe_to_email {
   my ($self, $action) = @_;

   return $self->delete_related
      ( 'deactivated', { sink => 'email', action => $action } );
}

sub subscribe_to_sms {
   my ($self, $action) = @_;

   return $self->delete_related
      ( 'deactivated', { sink => 'sms', action => $action } );
}

sub totp_authenticator {
   my $self = shift;

   return Auth::GoogleAuth->new( {
      issuer => $self->result_source->schema->config->title,
      key_id => $self->name,
      secret => $self->totp_secret,
   } );
}

sub unsubscribe_from_email {
   my ($self, $action) = @_;

   return $self->create_related
      ( 'deactivated', { sink => 'email', action => $action } );
}

sub unsubscribe_from_sms {
   my ($self, $action) = @_;

   return $self->create_related
      ( 'deactivated', { sink => 'sms', action => $action } );
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns );
   $self->validate( TRUE );
   $columns = { $self->get_inflated_columns };

   my $password = $columns->{password};

   $password and not is_encrypted( $password ) and $columns->{password}
      = $self->$_encrypt_password( $columns->{shortcode}, $password )
         and $self->set_inflated_columns( $columns );

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints      => {
         address       => { max_length =>  64, min_length => 0, },
         coordinates   => { max_length =>  16, min_length => 3, },
         email_address => { max_length =>  64, min_length => 0, },
         first_name    => { max_length =>  32, min_length => 1, },
         home_phone    => { max_length =>  16, min_length => 6, },
         last_name     => { max_length =>  32, min_length => 1, },
         location      => { max_length =>  24, min_length => 3, },
         mobile_phone  => { max_length =>  16, min_length => 6, },
         name          => { max_length =>  64, min_length => 3, },
         notes         => { max_length =>  VARCHAR_MAX_SIZE(),
                            min_length =>   0, },
         password      => { max_length => 128, min_length => 8, },
         postcode      => { max_length =>  16, min_length => 0, },
         region        => { max_length =>   1, min_length => 1, },
         shortcode     => { max_length =>   8, min_length => 5, },
      },
      fields           => {
         address       => { validate => 'isValidLength isValidText' },
         coordinates   => { validate => 'isValidLength' },
         badge_expires => { validate => 'isValidDate' },
         badge_id      => {
            unique     => TRUE,
            validate   => 'isValidInteger' },
         dob           => { validate => 'isValidDate' },
         email_address => {
            unique     => TRUE,
            validate   => 'isMandatory isValidLength isValidEmail' },
         first_name    => {
            filters    => 'filterUCFirst',
            validate   => 'isMandatory isValidLength isValidText' },
         home_phone    => { filters  => 'filterNonNumeric',
                            validate => 'isValidLength isValidInteger' },
         joined        => { validate => 'isValidDate' },
         last_name     => {
            filters    => 'filterUCFirst',
            validate   => 'isMandatory isValidLength isValidText' },
         location      => {
            filters    => 'filterUCFirst',
            validate   => 'isValidLength isValidText' },
         mobile_phone  => { filters  => 'filterNonNumeric',
                            validate => 'isValidLength isValidInteger' },
         name          => {
            unique     => TRUE,
            validate   => 'isMandatory isValidLength isSimpleText' },
         notes         => { validate => 'isValidLength isValidText' },
         password      => {
            validate   => 'isMandatory isValidLength isValidPassword' },
         postcode      => {
            filters    => 'filterUpperCase',
            validate   => 'isValidLength isValidPostcode' },
         region        => {
            filters    => 'filterUpperCase',
            validate   => 'isValidLength isSimpleText' },
         resigned      => { validate => 'isValidDate' },
         rows_per_page => { validate => 'isValidInteger' },
         shortcode     => {
            validate   => 'isMandatory isValidLength isValidIdentifier' },
         subscription  => { validate => 'isValidDate' },
      },
      level => 8,
   };
}

sub yield_slot {
   my ($self, $rota_name, $dt, $slot_name) = @_;

   my ($shift_type, $slot_type, $slotno) = split m{ _ }mx, $slot_name, 3;

   my $shift = $self->find_shift( $rota_name, $dt, $shift_type );
   my $slot  = $self->find_slot( $shift, $slot_type, $slotno );

   $slot or throw SlotFree, [ $slot ]; $self->$_assert_yield_allowed( $slot );

   return $slot->delete;
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

Copyright (c) 2017 Peter Flanigan. All rights reserved

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
