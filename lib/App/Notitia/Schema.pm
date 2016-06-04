package App::Notitia::Schema;

use namespace::autoclean;

use App::Notitia;
use App::Notitia::Constants qw( AS_PASSWORD COMMA EXCEPTION_CLASS FALSE NUL
                                OK QUOTED_RE SLOT_TYPE_ENUM SPC TRUE );
use App::Notitia::SMS;
use App::Notitia::Util      qw( build_schema_version encrypted_attr
                                load_file_data mail_domain to_dt );
use Archive::Tar::Constant  qw( COMPRESS_GZIP );
use Class::Usul::Functions  qw( create_token ensure_class_loaded
                                io is_member squeeze throw trim );
use Class::Usul::Types      qw( NonEmptySimpleStr );
use Data::Record;
use Data::Validation;
use DateTime                qw( );
use Scalar::Util            qw( blessed );
use Text::CSV;
use Try::Tiny;
use Unexpected::Functions   qw( PathNotFound Unspecified ValidationErrors );
use Moo;

extends q(Class::Usul::Schema);
with    q(App::Notitia::Role::Schema);
with    q(Web::Components::Role::Email);
with    q(Web::Components::Role::TT);

our $VERSION = $App::Notitia::VERSION;

# Attribute constructors
my $_build_admin_password = sub {
   my $self = shift; my $prompt = '+Database administrator password';

   return encrypted_attr $self->config, $self->config->ctlfile,
             'admin_password', sub { $self->get_line( $prompt, AS_PASSWORD ) };
};

# Public attributes (override defaults in base class)
has 'admin_password'  => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => $_build_admin_password;

has '+config_class'   => default => 'App::Notitia::Config';

has '+database'       => default => sub { $_[ 0 ]->config->database };

has '+schema_classes' => default => sub { $_[ 0 ]->config->schema_classes };

has '+schema_version' => default => sub { build_schema_version $VERSION };

# Construction
around 'deploy_file' => sub {
   my ($orig, $self, @args) = @_;

   $self->config->appclass->env_var( 'bulk_insert', TRUE );

   return $orig->( $self, @args );
};

# Private functions
my $_extend_column_map = sub {
   my ($cmap, $ncols) = @_; my $count = 0;

   for my $k (qw( active certifications endorsements name postcode password
                  roles nok_active nok_first_name nok_surname nok_name
                  nok_postcode nok_email nok_password vehicles )) {
      $cmap->{ $k } = $ncols + $count++;
   }

   return;
};

my $_make_key_from = sub {
   my $x = shift; my $k = lc squeeze trim $x; $k =~ s{ [ \-] }{_}gmx; return $k;
};

my $_natatime = sub {
   my $n = shift; my @list = @_;

   return sub { return $_[ 0 ] ? unshift @list, @_ : splice @list, 0, $n };
};

my $_word_iter = sub {
   my ($n, $field) = @_; $field =~ s{[\(\)]}{\"}gmx;

   my $splitter = Data::Record->new( { split => SPC, unless => QUOTED_RE } );

   return $_natatime->( $n, $splitter->records( $field ) );
};

# Private methods
my $_populate_blots = sub {
   my ($self, $dv, $cmap, $lno, $cols) = @_;

   my $tc_map = $self->config->import_people->{pcode2blot_map};
   my $x_map  = $self->config->import_people->{extra2csv_map};
   my $iter   = $_word_iter->( 3, $cols->[ $cmap->{ $x_map->{blots} } ] );

   while (my @vals = $iter->()) {
      my $endorsed; try { $endorsed = to_dt $vals[ 2 ] } catch {};

      if ($vals[ 0 ] =~ m{ \A \d+ \z }mx and $endorsed) {
         my $endorsement = {
            endorsed  => $endorsed,
            points    => $vals[ 0 ],
            type_code => $tc_map->{ uc $vals[ 1 ] } // $vals[ 1 ] };
         my @peek = $iter->(); my $notes;

         if ($peek[ 0 ]) {
            $peek[ 0 ] !~ m{ \A \d+ \z }mx and $notes = shift @peek;
            $peek[ 0 ] and $iter->( @peek );
         }

         $notes and $notes =~ s{ [\'\"] }{}gmx;
         $notes and $endorsement->{notes} = ucfirst $notes;
         push @{ $cols->[ $cmap->{endorsements} ] }, $endorsement;
      }
      else { shift @vals; $vals[ 0 ] and $iter->( @vals ) }
   }

   return;
};

my $_populate_certs = sub {
   my ($self, $dv, $cmap, $lno, $cols) = @_;

   my $x_map = $self->config->import_people->{extra2csv_map};
   my $iter  = $_word_iter->( 2, $cols->[ $cmap->{ $x_map->{m_advanced} } ] );

   while (my @vals = $iter->()) {
      my $completed; try { $completed = to_dt $vals[ 1 ] } catch {};

      if ($completed) {
         my $certification = { completed => $completed, type => 'm_advanced' };
         my $notes = $vals[ 0 ]; $notes and $notes =~ s{ [\'\"] }{}gmx;

         $notes and $certification->{notes} = $notes;
         push @{ $cols->[ $cmap->{certifications} ] }, $certification;
      }
      else { shift @vals; $vals[ 0 ] and $iter->( @vals ) }
   }

   return;
};

my $_populate_certs_from_roles = sub {
   my ($self, $cmap, $cols) = @_;

   my $roles = $cols->[ $cmap->{roles} ] //= [];
   my $certs = $cols->[ $cmap->{certifications} ] //= [];

   $roles->[ 0 ] or return; my $conf = $self->config;

   my $date = to_dt( '1/1/1970' )->set_time_zone( 'local' );

   (is_member 'bike_rider', $roles
    or is_member 'm_advanced', [ map { $_->{type} } @{ $certs } ])
      and push @{ $certs }, { completed => $date, type => 'catagory_a' };
   is_member 'controller', $roles
      and push @{ $certs }, { completed => $date, type => 'controller' };
   is_member 'driver', $roles
      and push @{ $certs }, { completed => $date, type => 'catagory_b' };

   for my $role (values %{ $conf->import_people->{rcode2role_map} }) {
      is_member $role, $roles
         and push @{ $certs }, { completed => $date, type => 'gmp' }
         and last;
   }

   return;
};

my $_populate_postcode = sub {
   my ($self, $dv, $cmap, $lno, $cols, $prefix) = @_; $prefix //= NUL;

   my $p2cmap     = $self->config->import_people->{person2csv_map};
   my $address    = $cols->[ $cmap->{ $prefix.$p2cmap->{address} } ];
   my ($postcode) = $address =~ m{ ([a-zA-Z0-9]+ \s? [a-zA-Z0-9]+) \z }mx;

   try {
      $dv->check_field( 'postcode', $postcode );
      $address =~ s{ ([a-zA-Z0-9]+ \s? [a-zA-Z0-9]+) \z }{}mx;
      $cols->[ $cmap->{ $prefix.$p2cmap->{address } } ] = $address;
      $cols->[ $cmap->{ $prefix.$p2cmap->{postcode} } ] = $postcode;
   }
   catch {
      $self->warning( 'Bad postcode line [_1]: [_2]',
         { args => [ $lno, $postcode ], no_quote_bind_values => TRUE } );
      $cols->[ $cmap->{ $prefix.$p2cmap->{address } } ] = $address;
   };

   return;
};

my $_populate_nok_columns = sub {
   my ($self, $dv, $cmap, $lno, $cols, $nok) = @_;

   my $p2cmap = $self->config->import_people->{person2csv_map};

   $cols->[ $cmap->{ 'nok_'.$p2cmap->{active} } ] = FALSE;

   ($cols->[ $cmap->{ 'nok_'.$p2cmap->{first_name} } ],
    $cols->[ $cmap->{ 'nok_'.$p2cmap->{last_name } } ])
      = split SPC, (squeeze trim $nok), 2;

   my $name = lc $cols->[ $cmap->{ 'nok_'.$p2cmap->{first_name} } ].'.'
            .    $cols->[ $cmap->{ 'nok_'.$p2cmap->{last_name } } ];

   $name =~ s{[ \'\-\+]}{}gmx;
   $cols->[ $cmap->{ 'nok_'.$p2cmap->{name} } ] = $name;

   $cols->[ $cmap->{ 'nok_'.$p2cmap->{email_address} } ]
      = lc $cols->[ $cmap->{ 'nok_'.$p2cmap->{name} } ].'@example.com';

   $cols->[ $cmap->{ 'nok_'.$p2cmap->{password} } ]
      = substr create_token, 0, 12;

   $cols->[ $cmap->{ 'nok_'.$p2cmap->{address} } ] or
      $cols->[ $cmap->{ 'nok_'.$p2cmap->{address} } ]
         = $cols->[ $cmap->{ $p2cmap->{address } } ].SPC
         . $cols->[ $cmap->{ $p2cmap->{postcode} } ];

   $self->$_populate_postcode( $dv, $cmap, $lno, $cols, 'nok_' );
   return;
};

my $_populate_member_columns = sub {
   my ($self, $dv, $cmap, $lno, $cols) = @_;

   my $p2cmap = $self->config->import_people->{person2csv_map};
   my $x_map  = $self->config->import_people->{extra2csv_map};

   $cols->[ $cmap->{ $p2cmap->{active} } ] = TRUE;

   my $name = lc $cols->[ $cmap->{ $p2cmap->{first_name} } ].'.'
            .    $cols->[ $cmap->{ $p2cmap->{last_name } } ];

   $name =~ s{[ \'\-\+]}{}gmx; $cols->[ $cmap->{ $p2cmap->{name} } ] = $name;

   $cols->[ $cmap->{ $p2cmap->{email_address} } ]
      or $cols->[ $cmap->{ $p2cmap->{email_address} } ]
            = $cols->[ $cmap->{ $p2cmap->{name} } ].'@example.com';

   $cols->[ $cmap->{ $p2cmap->{password} } ] = substr create_token, 0, 12;

   $self->$_populate_blots( $dv, $cmap, $lno, $cols );
   $self->$_populate_certs( $dv, $cmap, $lno, $cols );
   $self->$_populate_postcode( $dv, $cmap, $lno, $cols );

   for my $col (qw( joined subscription )) {
      my $i = $cmap->{ $p2cmap->{ $col } }; defined $cols->[ $i ]
         and $cols->[ $i ] = to_dt $cols->[ $i ];
   }

   if (my $duties = $cols->[ $cmap->{ $x_map->{roles} } ]) {
      my $map = $self->config->import_people->{rcode2role_map};

      for my $duty (map { uc } split m{}mx, $duties) {
         $map->{ $duty }
            and push @{ $cols->[ $cmap->{roles} ] }, $map->{ $duty };
      }
   }

   return;
};

my $_populate_vehicles = sub {
   my ($self, $cmap, $cols) = @_;

   my $x_map    = $self->config->import_people->{extra2csv_map};
   my $splitter = Data::Record->new( { split => COMMA, unless => QUOTED_RE } );
   my $vehicles = squeeze trim $cols->[ $cmap->{ $x_map->{vehicles} } ];
   my @vehicles = $splitter->records( $vehicles );

   for my $vehicle (map { s{[:]}{}mx; $_ } @vehicles) {
      my ($type, $vrn, $desc) = split SPC, $vehicle, 3;

      push @{ $cols->[ $cmap->{vehicles} ] },
            { notes => $desc, type => lc $type, vrn => uc $vrn };
   }

   return;
};

my $_list_participents = sub {
   my $self      = shift;
   my $uri       = $self->options->{event};
   my $event     = $self->schema->resultset( 'Event' )->find_event_by( $uri );
   my $opts      = { columns => [ 'email_address', 'mobile_phone' ] };
   my $person_rs = $self->schema->resultset( 'Person' );

   return $person_rs->list_participents( $event, $opts );
};

my $_list_people = sub {
   my $self      = shift;
   my $person_rs = $self->schema->resultset( 'Person' );
   my $opts      = { columns => [ 'email_address', 'mobile_phone' ] };
   my $role      = $self->options->{role};

   not defined $self->options->{current} and $opts->{current} = TRUE;

   return $role ? $person_rs->list_people( $role, $opts )
                : $person_rs->list_all_people( $opts );
};

my $_qualify_assets = sub {
   my ($self, $files) = @_; $files or return FALSE; my $assets = {};

   for my $file (@{ $files }) {
      my $path = $self->config->assetdir->catfile( $file );

      $path->exists or $path = io $file; $path->exists or next;

      $assets->{ $path->basename } = $path;
   }

   return $assets;
};

my $_send_email = sub {
   my ($self, $template, $person, $stash, $attaches) = @_;

   $person->email_address =~ m{ \@ example\.com \z }imx and return;

   $template = "[% WRAPPER 'hyde/email_layout.tt' %]${template}[% END %]";

   $stash->{first_name} = $person->first_name;
   $stash->{last_name } = $person->last_name;
   $stash->{username  } = $person->name;

   my $post   = {
      attributes      => {
         charset      => $self->config->encoding,
         content_type => 'text/html', },
      from            => $self->config->title.'@'.mail_domain(),
      stash           => $stash,
      subject         => $stash->{subject} // 'No subject',
      template        => \$template,
      to              => $person->email_address, };

   $attaches and $post->{attachments} = $attaches;

   my $r      = $self->send_email( $post );
   my ($id)   = $r =~ m{ ^ OK \s+ id= (.+) $ }msx; chomp $id;
   my $params = { args => [ $person->shortcode, $id ] };

   $self->info( 'Emailed [_1] - [_2]', $params );
   return;
};

my $_send_sms = sub {
   my ($self, $template, $tuples, $stash) = @_; my @recipients;

   my $conf = $self->config; my $attr = $stash->{sms_attributes} // {};

   $stash->{template}->{layout} = \$template;

   $attr->{log     } //= $self->log;
   $attr->{password} //= $conf->sms_password;
   $attr->{username} //= $conf->sms_username;

   my $sender  = App::Notitia::SMS->new( $attr );
   my $message = $self->render_template( $stash );

   for my $person (map { $_->[ 1 ] } @{ $tuples }) {
      $person->mobile_phone and push @recipients, $person->mobile_phone;
   }

   my $rv = $sender->send_sms( $message, @recipients );

   $self->info( 'SMS message rv: [_1]', { args => [ $rv ] } );
   return;
};

my $_update_person = sub {
   my ($conf, $person, $person_attr) = @_;

   my $p2cmap = $conf->import_people->{person2csv_map};

   for my $col (grep { $_ ne 'roles' } keys %{ $p2cmap }) {
      exists $person_attr->{ $col } and defined $person_attr->{ $col }
         and $person->$col( $person_attr->{ $col } );
   }

   return $person->update;
};

my $_import_code = sub {
   my ($self, $cmap, $cols, $has_nok, $nok, $person, $person_attr) = @_;

   my $cert_rs    = $self->schema->resultset( 'Certification' );
   my $blot_rs    = $self->schema->resultset( 'Endorsement' );
   my $vehicle_rs = $self->schema->resultset( 'Vehicle' );

   return sub {
      $self->dry_run and return;
      $has_nok and not $nok->in_storage and $nok->insert;
      $has_nok and $person->next_of_kin_id( $nok->id );

      if (not $person->in_storage) { $person->insert }
      else { $_update_person->( $self->config, $person, $person_attr ) }

      for my $role (@{ $cols->[ $cmap->{roles} ] }) {
         $person->add_member_to( $role );
      }

      for my $cert_attr (@{ $cols->[ $cmap->{certifications} ] }) {
         $cert_attr->{recipient_id} = $person->id;
         try { $cert_rs->create( $cert_attr ) } catch {
            $self->warning( 'Cert. creation failed: [_1]',
                            { args => [ $_ ], no_quote_bind_values => TRUE } );
         };
      }

      for my $blot_attr (@{ $cols->[ $cmap->{endorsements} ] }) {
         $blot_attr->{recipient_id} = $person->id;
         try { $blot_rs->create( $blot_attr ) } catch {
            $self->warning( 'Endorsement creation failed: [_1]',
                            { args => [ $_ ], no_quote_bind_values => TRUE } );
         };
      }

      for my $vehicle_attr (@{ $cols->[ $cmap->{vehicles} ] }) {
         $vehicle_attr->{owner_id} = $person->id;
         try { $vehicle_rs->create( $vehicle_attr ) } catch {
            $self->warning( 'Vehicle creation failed: [_1]',
                            { args => [ $_ ], no_quote_bind_values => TRUE } )
         };
      }

      return;
   };
};

my $_update_or_new_person = sub {
   my ($self, $cmap, $cols, $nok_attr, $person_attr) = @_;

   my $has_nok   = $nok_attr->{email_address} ? TRUE : FALSE;
   my $person_rs = $self->schema->resultset( 'Person' );

   try   {
      my $nok; $has_nok and $nok
         = $person_rs->find_or_new( $nok_attr, { key => 'person_name' } );
      my $person = $person_rs->find_or_new
         ( $person_attr, { key => 'person_name' } );

      $self->schema->txn_do( $self->$_import_code
         ( $cmap, $cols, $has_nok, $nok, $person, $person_attr ) );

      $self->info( 'Created [_1]([_2])',
                   { args => [ $person->label, $person->shortcode ],
                     no_quote_bind_values => TRUE }  );
   }
   catch {
      if ($_->can( 'class' ) and $_->class eq ValidationErrors->()) {
         $self->warning( $_ ) for (@{ $_->args });
      }
      else { $self->warning( $_ ) }
   };

   return;
};

my $_create_person = sub {
   my ($self, $csv, $ncols, $dv, $cmap, $lno, $line) = @_; $lno++;

   my $status = $csv->parse( $line ); my @columns = $csv->fields();

   my $p2cmap = $self->config->import_people->{person2csv_map};

   $columns[ $cmap->{ $p2cmap->{first_name} } ] or return $lno;

   my $columns = [ splice @columns, 0, $ncols ];
   my $x_map   = $self->config->import_people->{extra2csv_map};

   $self->$_populate_member_columns( $dv, $cmap, $lno, $columns );

   if (my $nok = $columns->[ $cmap->{ $x_map->{next_of_kin} } ]) {
      $self->$_populate_nok_columns( $dv, $cmap, $lno, $columns, $nok );
   }

   $self->$_populate_certs_from_roles( $cmap, $columns );
   $self->$_populate_vehicles( $cmap, $columns );

   my $nok_attr = {}; my $person_attr = {};

   for my $col (grep { $_ ne 'roles' } keys %{ $p2cmap }) {
      my $i = $cmap->{ 'nok_'.$p2cmap->{ $col } };
      my $v; defined $i and $v = $columns->[ $i ]
         and $nok_attr->{ $col } = squeeze trim $v;

      $person_attr->{ $col }
         = squeeze trim $columns->[ $cmap->{ $p2cmap->{ $col } } ];
   }

   $self->debug and $self->dumper( $columns, $nok_attr, $person_attr );
   $self->$_update_or_new_person( $cmap, $columns, $nok_attr, $person_attr );

   return $lno;
};

# Public methods
sub backup_data : method {
   my $self = shift;
   my $now  = DateTime->now;
   my $conf = $self->config;
   my $date = $now->ymd( NUL ).'-'.$now->hms( NUL );
   my $file = $self->database."-${date}.sql";
   my $path = $conf->tempdir->catfile( $file );
   my $bdir = $conf->vardir->catdir( 'backups' );
   my $tarb = $conf->title."-${date}.tgz";
   my $out  = $bdir->catfile( $tarb )->assert_filepath;

   if (lc $self->driver eq 'mysql') {
      $self->run_cmd
         ( [ 'mysqldump', '--opt', '--host', $self->host,
             '--password='.$self->admin_password, '--result-file',
             $path->pathname, '--user', $self->db_admin_ids->{mysql},
             '--databases', $self->database ] );
   }

   ensure_class_loaded 'Archive::Tar'; my $arc = Archive::Tar->new;

   chdir $conf->appldir;
   $path->exists and $arc->add_files( $path->abs2rel( $conf->appldir ) );

   for my $doc ($conf->docs_root->clone->deep->all_files) {
      $arc->add_files( $doc->abs2rel( $conf->appldir ) );
   }

   for my $cfgfile (map { io $_ } @{ $conf->cfgfiles }) {
      $arc->add_files( $cfgfile->abs2rel( $conf->appldir ) );
   }

   my $localedir = $conf->localedir
                        ->clone->filter( sub { m{ _local\.po \z }mx } )->deep;

   for my $pofile ($localedir->all_files ) {
      $arc->add_files( $pofile->abs2rel( $conf->appldir ) );
   }

   $self->info( 'Generating backup [_1]', { args => [ $tarb ] } );
   $arc->write( $out->pathname, COMPRESS_GZIP ); $path->unlink;

   return OK;
}

sub dump_connect_attr : method {
   my $self = shift; $self->dumper( $self->connect_info ); return OK;
}

sub deploy_and_populate : method {
   my $self    = shift; $self->db_attr->{ignore_version} = TRUE;
   my $rv      = $self->SUPER::deploy_and_populate;
   my $type_rs = $self->schema->resultset( 'Type' );
   my $sc_rs   = $self->schema->resultset( 'SlotCriteria' );

   for my $slot_type (@{ SLOT_TYPE_ENUM() }) {
      for my $cert_name (@{ $self->config->slot_certs->{ $slot_type } }) {
         my $cert = $type_rs->find_certification_by( $cert_name );

         $sc_rs->create( { slot_type             => $slot_type,
                           certification_type_id => $cert->id } );
      }
   }

   return $rv;
}

sub import_people : method {
   my $self   = shift;
   my $file   = $self->next_argv or throw Unspecified, [ 'file name' ];
   my $f_io   = io $file;
   my $csv    = Text::CSV->new ( { binary => 1 } )
                or throw Text::CSV->error_diag();
   my $status = $csv->parse( $f_io->getline );
   my $f      = FALSE;
   my $cno    = 0;
   my $cmap   = { map { $_make_key_from->( $_->[ 0 ] ) => $_->[ 1 ] }
                  map { [ $_ ? $_ : "col${cno}", $cno++ ] }
                  reverse grep { $_ and $f = TRUE; $f }
                  reverse $csv->fields() };
   my $ncols  = keys %{ $cmap }; $_extend_column_map->( $cmap, $ncols );

   $self->debug and $self->dumper( $cmap );

   ensure_class_loaded my $class = (blessed $self->schema).'::Result::Person';

   my $dv = Data::Validation->new( $class->validation_attributes ); my $lno = 1;

   while (defined (my $line = $f_io->getline)) {
      $lno = $self->$_create_person( $csv, $ncols, $dv, $cmap, $lno, $line );
   }

   $self->config->badge_mtime->touch;

   return OK;
}

sub send_message : method {
   my $self       = shift;
   my $conf       = $self->config;
   my $plate_name = $self->next_argv or throw Unspecified, [ 'template name' ];
   my $sink       = $self->next_argv // 'email';
   my $quote      = $self->next_argv ? TRUE : FALSE;
   my $stash      = { app_name       => $conf->title,
                      path           => io( $plate_name ),
                      sms_attributes => { quote => $quote }, };
   my $template   = load_file_data( $stash );
   my $attaches   = $self->$_qualify_assets( delete $stash->{attachments} );
   my $tuples     = $self->options->{event} ? $self->$_list_participents
                                            : $self->$_list_people;

   if ($sink eq 'sms') { $self->$_send_sms( $template, $tuples, $stash ) }
   else {
      for my $person (map { $_->[ 1 ] } @{ $tuples }) {
         $self->$_send_email( $template, $person, $stash, $attaches );
      }
   }

   return OK;
}

sub restore_data : method {
   my $self = shift; my $conf = $self->config;

   my $path = $self->next_argv or throw Unspecified, [ 'pathname' ];

   $path = io $path; $path->exists or throw PathNotFound, [ $path ];

   ensure_class_loaded 'Archive::Tar'; my $arc = Archive::Tar->new;

   chdir $conf->appldir; $arc->read( $path->pathname ); $arc->extract();

   my (undef, $date) = split m{ - }mx, $path->basename( '.tgz' ), 2;
   my $bdir = $conf->vardir->catdir( 'backups' );
   my $sql  = $conf->tempdir->catfile( $conf->database."-${date}.sql" );

   if ($sql->exists and lc $self->driver eq 'mysql') {
      $self->run_cmd
         ( [ 'mysql', '--host', $self->host,
             '--password='.$self->admin_password, '--user',
             $self->db_admin_ids->{mysql}, $self->database ],
           { in => $sql } );
      $sql->unlink;
   }

   return OK;
}

sub runqueue : method {
   my $self = shift;

   $self->lock->set( k => 'runqueue' );

   for my $job ($self->schema->resultset( 'Job' )->search( {} )->all) {
      try {
         $self->info( 'Running job [_1]-[_2]',
                      { args => [ $job->name, $job->id ] } );

         my $r = $self->run_cmd( [ split SPC, $job->command ] );

         $self->info( 'Job [_1]-[_2] rv [_3]',
                      { args => [ $job->name, $job->id, $r->rv ] } );
      }
      catch {
         $self->error( 'Job [_1]-[_2] rv [_3]: [_4]',
                       { args => [ $job->name, $job->id, $_->rv, "${_}" ],
                         no_quote_bind_values => TRUE } );
      };

      $job->delete;
   }

   $self->lock->reset( k => 'runqueue' );

   return OK;
}

sub upgrade_schema : method {
   my $self = shift;

   $self->schema->upgrade_directory( $self->config->sharedir);
   $self->schema->upgrade;
   return OK;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head2 C<backup_data> - Creates a backup of the database and documents

=head2 C<dump_connect_attr> - Displays database connection information

=head2 C<deploy_and_populate> - Create tables and populates them with initial data

=head2 C<import_people> - Import person objects from a CSV file

=head2 C<send_message> - Send email or SMS to people

=head2 C<restore_data> - Restore a backup of the database and documents

=head2 C<runqueue> - Process the queue of background tasks

=head2 C<upgrade_schema> - Upgrade the database schema

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
