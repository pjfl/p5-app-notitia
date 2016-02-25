package App::Notitia::Config;

use namespace::autoclean;

use Class::Usul::Constants       qw( FALSE NUL TRUE );
use Class::Usul::Crypt::Util     qw( decrypt_from_config encrypt_for_config );
use Class::Usul::File;
use Class::Usul::Functions       qw( class2appdir create_token );
use Data::Validation::Constants  qw( );
use File::DataClass::Types       qw( ArrayRef Bool CodeRef Directory File
                                     HashRef NonEmptySimpleStr
                                     NonNumericSimpleStr
                                     NonZeroPositiveInt Object Path
                                     PositiveInt SimpleStr Str Undef );
use Web::ComposableRequest::Util qw( extract_lang );
use Moo;

extends q(Class::Usul::Config::Programs);

# Attribute constructors
my $_build_cdnjs = sub {
   my $self  = shift;
   my %cdnjs = map { $_->[ 0 ] => $self->cdn.$_->[ 1 ] } @{ $self->jslibs };

   return \%cdnjs;
};

my $_build_components = sub {
   my $self = shift; my $conf = {};

   for my $name (keys %{ $self->_components } ) {
      for my $k (keys %{ $self->_components->{ $name } }) {
         $conf->{ $name }->{ $k } = $self->_components->{ $name }->{ $k };
      }
   }

   return $conf;
};

my $_build_secret = sub {
   my $self = shift; my $file = $self->ctlfile; my $data = {}; my $token;

   if ($file->exists) {
      $data  = Class::Usul::File->data_load( paths => [ $file ] ) // {};
      $token = decrypt_from_config $self, $data->{secret};
   }

   unless ($token) {
      $data->{secret} = encrypt_for_config $self, $token = create_token;
      Class::Usul::File->data_dump( { path => $file->assert, data => $data } );
   }

   return $token;
};

my $_build_user_home = sub {
   my $appldir = $_[ 0 ]->appldir; my $verdir = $appldir->basename;

   return $verdir =~ m{ \A v \d+ \. \d+ p (\d+) \z }msx
        ? $appldir->dirname : $appldir;
};

sub _build_l10n_domains {
   my $prefix = $_[ 0 ]->prefix; return [ $prefix, "${prefix}-".$_[ 0 ]->name ];
}

# Public attributes
has 'brand'           => is => 'ro',   isa => SimpleStr, default => NUL;

has 'cdn'             => is => 'ro',   isa => SimpleStr, default => NUL;

has 'cdnjs'           => is => 'lazy', isa => HashRef,
   builder            => $_build_cdnjs, init_arg => undef;

has 'components'      => is => 'lazy', isa => HashRef,
   builder            => $_build_components, init_arg => undef;

has 'compress_css'    => is => 'ro',   isa => Bool, default => TRUE;

has 'connect_params'  => is => 'ro',   isa => HashRef,
   builder            => sub { { quote_names => TRUE } };

has 'css'             => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'css';

has 'database'        => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'schedule';

has 'default_route'   => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => sub {
      (my $mp = $_[ 0 ]->mount_point) =~ s{ \A / \z }{}mx; "${mp}/index" };

has 'default_view'    => is => 'ro',   isa => SimpleStr, default => 'html';

has 'deflate_types'   => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub {
      [ qw( text/css text/html text/javascript application/javascript ) ] };

has 'description'     => is => 'ro',   isa => SimpleStr, default => NUL;

has 'images'          => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'img';

has 'js'              => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'js';

has 'jslibs'          => is => 'ro',   isa => ArrayRef, builder => sub { [] };

has 'keywords'        => is => 'ro',   isa => SimpleStr, default => NUL;

has 'languages'       => is => 'lazy', isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub { [ map { extract_lang $_ } @{ $_[0]->locales } ]},
   init_arg           => undef;

has 'layout'          => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'standard';

has 'less'            => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'less';

has 'less_files'      => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub { [ qw( yellow ) ] };

has 'load_factor'     => is => 'ro',   isa => NonZeroPositiveInt,
   default            => 14;

has 'max_messages'    => is => 'ro',   isa => NonZeroPositiveInt, default => 3;

has 'max_sess_time'   => is => 'ro',   isa => PositiveInt, default => 3_600;

has 'mount_point'     => is => 'ro',   isa => NonEmptySimpleStr,
   default            => '/notitia';

has 'no_index'        => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub {
      [ qw( \.git$ \.htpasswd$ \.json$ \.mtime$ \.svn$ assets$ posts$ ) ] };

has 'no_user_email'   => is => 'ro',   isa => Bool, default => FALSE;

has 'owner'           => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => sub { $_[ 0 ]->prefix };

has 'port'            => is => 'lazy', isa => NonZeroPositiveInt,
   default            => 8085;

has 'repo_url'        => is => 'ro',   isa => SimpleStr, default => NUL;

has 'request_roles'   => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub { [ 'L10N', 'Session', 'JSON', 'Cookie' ] };

has 'schema_classes'  => is => 'ro',   isa => HashRef[NonEmptySimpleStr],
   builder            => sub { {
      'schedule'      => 'App::Notitia::Schema::Schedule', } };

has 'scrubber'        => is => 'ro',   isa => Str,
   default            => '[^ +\-\./0-9@A-Z\\_a-z~]';

has 'secret'          => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => $_build_secret;

has 'serve_as_static' => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'css | favicon.ico | fonts | img | js | less';

has 'server'          => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'Starman';

has 'session_attr'    => is => 'lazy', isa => HashRef[ArrayRef],
   builder            => sub { {
      query           => [ SimpleStr | Undef                ],
      skin            => [ NonEmptySimpleStr, $_[ 0 ]->skin ],
      theme           => [ NonEmptySimpleStr, 'yellow'      ], } };

has 'skin'            => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'hyde';

has 'slot_limits'     => is => 'ro',   isa => ArrayRef[PositiveInt],
   builder            => sub { [ 2, 1, 3, 3, 1, 1 ] };

has 'stash_attr'      => is => 'lazy', isa => HashRef[ArrayRef],
   builder            => sub { {
      config          => [ qw( description keywords ) ],
      links           => [ qw( css images js ) ],
      request         => [ qw( authenticated host language locale username ) ],
      session         => [ sort keys %{ $_[ 0 ]->session_attr } ], } };

has 'title'           => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'Notitia';

has 'user'            => is => 'ro',   isa => SimpleStr, default => NUL;

has 'user_home'       => is => 'lazy', isa => Path, coerce => TRUE,
   builder            => $_build_user_home;

has 'workers'         => is => 'ro',   isa => NonZeroPositiveInt, default => 5;

# Private attributes
has '_components'     => is => 'ro',   isa => HashRef,
   builder            => sub { {} }, init_arg => 'components';

# Attribute constructors
sub _build_ctlfile {
   my $name      = class2appdir $_[ 0 ]->inflate_symbol( $_[ 1 ], 'appclass' );
   my $extension = $_[ 0 ]->inflate_symbol( $_[ 1 ], 'extension' );

   return $_[ 0 ]->inflate_path( $_[ 1 ], 'ctrldir', $name.$extension );
}

sub _build__l10n_attributes {
   return { gettext_catagory => NUL, };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Config - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Config;
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
