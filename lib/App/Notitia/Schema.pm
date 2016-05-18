package App::Notitia::Schema;

use namespace::autoclean;

use App::Notitia;
use App::Notitia::Constants qw( AS_PASSWORD EXCEPTION_CLASS FALSE NUL
                                OK SLOT_TYPE_ENUM TRUE );
use App::Notitia::SMS;
use App::Notitia::Util      qw( encrypted_attr load_file_data mail_domain );
use Archive::Tar::Constant  qw( COMPRESS_GZIP );
use Class::Usul::Functions  qw( ensure_class_loaded io throw );
use Class::Usul::Types      qw( NonEmptySimpleStr );
use DateTime                qw( );
use Try::Tiny;
use Unexpected::Functions   qw( PathNotFound Unspecified );
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

my $_build_schema_version = sub {
   my ($major, $minor) = $VERSION =~ m{ (\d+) \. (\d+) }mx;

   # TODO: This will break when major number bumps
   return $major.'.'.($minor + 1);
};

# Public attributes (override defaults in base class)
has 'admin_password'  => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => $_build_admin_password;

has '+config_class'   => default => 'App::Notitia::Config';

has '+database'       => default => sub { $_[ 0 ]->config->database };

has '+schema_classes' => default => sub { $_[ 0 ]->config->schema_classes };

has '+schema_version' => default => $_build_schema_version;

# Construction
around 'deploy_file' => sub {
   my ($orig, $self, @args) = @_;

   $self->config->appclass->env_var( 'bulk_insert', TRUE );

   return $orig->( $self, @args );
};

# Private methods
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
   my ($self, $stash, $template, $attaches, $person) = @_;

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
   my ($self, $stash, $template, $tuples) = @_; my @recipients;

   $stash->{template}->{layout} = \$template;

   my $conf    = $self->config;
   my $attr    = { log      => $self->log,
                   password => $conf->sms_password,
                   username => $conf->sms_username };
   my $sender  = App::Notitia::SMS->new( $attr );
   my $message = $self->render_template( $stash );

   for my $person (map { $_->[ 1 ] } @{ $tuples }) {
      $person->mobile_phone and push @recipients, $person->mobile_phone;
   }

   $sender->send_sms( $message, @recipients );
   return;
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
   my $self    = shift;
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
};

sub mailshot : method {
   my $self       = shift;
   my $conf       = $self->config;
   my $plate_name = $self->next_argv or throw Unspecified, [ 'template name' ];
   my $sink       = $self->next_argv // 'email';
   my $stash      = { app_name => $conf->title, path => io( $plate_name ), };
   my $template   = load_file_data( $stash );
   my $attaches   = $self->$_qualify_assets( delete $stash->{attachments} );
   my $tuples     = $self->options->{event} ? $self->$_list_participents
                                            : $self->$_list_people;

   if ($sink eq 'sms') { $self->$_send_sms( $stash, $template, $tuples ) }
   else {
      for my $person (map { $_->[ 1 ] } @{ $tuples }) {
         $self->$_send_email( $stash, $template, $attaches, $person );
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
