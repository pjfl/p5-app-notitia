package App::Notitia::Model;

use App::Notitia::Attributes;  # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( bind field_options uri_for_action );
use Class::Usul::Functions  qw( ensure_class_loaded exception
                                first_char throw );
use Class::Usul::Types      qw( Object Plinth );
use Data::Validation;
use HTTP::Status            qw( HTTP_BAD_REQUEST HTTP_NOT_FOUND HTTP_OK );
use JSON::MaybeXS;
use Scalar::Util            qw( blessed );
use Try::Tiny;
use Unexpected::Functions   qw( Authentication AuthenticationRequired
                                ValidationErrors );
use Moo;

with q(Web::Components::Role);

# Public attributes
has 'application' => is => 'ro',   isa => Plinth,
   required       => TRUE,    weak_ref => TRUE;

has 'transcoder'  => is => 'lazy', isa => Object,
   builder        => sub { JSON::MaybeXS->new( utf8 => FALSE ) };

# Private class attributes
my $_result_class_cache = {};

# Private functions
my $_auth_redirect = sub {
   my ($req, $e, $summary) = @_;

   if ($e->class eq AuthenticationRequired->()) {
      my $location = uri_for_action $req, 'user/login';

      $req->session->wanted( $req->path );

      return { redirect => { location => $location, message => [ $summary ] } };
   }

   if ($e->instance_of( Authentication->() )) {
      my $location = uri_for_action $req, 'user/login';

      return { redirect => { location => $location, message => [ $summary ] } };
   }

   return;
};

# Private methods
my $_check_field = sub {
   my ($self, $req, $class_base) = @_;

   my $params = $req->query_params;
   my $domain = $params->( 'domain' );
   my $class  = $params->( 'form'   );
   my $id     = $params->( 'id'     );
   my $val    = $params->( 'val', { raw => TRUE } );

   if    (first_char $class eq '+') { $class = substr $class, 1 }
   elsif (defined $class_base)      { $class = "${class_base}::${class}" }

   $_result_class_cache->{ $class }
      or (ensure_class_loaded( $class )
          and $_result_class_cache->{ $class } = TRUE);

   my $attr = $class->validation_attributes; $attr->{level} = 4;

   return Data::Validation->new( $attr )->check_field( $id, $val );
};

# Public methods
sub bind_fields {
   my ($self, $src, $map, $result) = @_;

   my $schema = $self->schema; my $fields = {};

   for my $k (keys %{ $map }) {
      my $value = exists $map->{ $k }->{checked} ? TRUE : $src->$k();
      my $opts  = field_options( $schema, $result, $k, $map->{ $k } );

      $fields->{ $k } = bind( $k, $value, $opts );
   }

   return $fields;
}

sub check_field_server {
   my ($self, $k, $opts) = @_;

   my $args = $self->transcoder->encode
      ( [ $k, $opts->{form}, $opts->{domain} ] );

   return "   behaviour.config.server[ '${k}' ] = {",
          "      method    : 'checkField',",
          "      event     : 'blur',",
          "      args      : ${args} };";
}

sub check_form_field {
   my ($self, $req, $result_class_base) = @_; my $mesg;

   my $id = $req->query_params->( 'id' ); my $meta = { id => "${id}_ajax" };

   try   { $self->$_check_field( $req, $result_class_base ) }
   catch {
      my $e = $_; my $args = { params => $e->args };

      $self->log->debug( "${e}" );
      $mesg = $req->loc( $e->error, $args );
      $meta->{class_name} = 'field-error';
   };

   return { code => HTTP_OK,
            page => { content => { html => $mesg }, meta => $meta },
            view => 'json' };
}

sub dialog_anchor {
   my ($self, $k, $href, $opts) = @_;

   my $args = $self->transcoder->encode( [ "${href}", $opts ] );

   return "   behaviour.config.anchors[ '${k}' ] = {",
          "      method    : 'modalDialog',",
          "      args      : ${args} };";
}

sub dialog_stash {
   my ($self, $req, $layout) = @_; my $stash = $self->initialise_stash( $req );

   $stash->{page} = $self->load_page( $req, {
      fields => {},
      layout => $layout,
      meta   => { id => $req->query_params->( 'id' ), }, } );
   $stash->{view} = 'json';

   return $stash;
}

sub exception_handler {
   my ($self, $req, $e) = @_; my ($leader, $message, $summary);

   if ($e =~ m{ : }mx) {
      ($leader, $message) = split m{ : }mx, "${e}", 2;
      $summary = substr $message, 0, 500;
   }
   else { $leader = NUL; $summary = $message = "${e}" }

   my $redirect = $_auth_redirect->( $req, $e, $summary );
      $redirect and return $redirect;

   my $opts = { params   => [ $req->username ], no_quote_bind_values => TRUE };
   my $page = { error    => $e,
                leader   => $leader,
                message  => $message,
                summary  => $summary,
                template => [ 'contents', 'exception' ],
                title    => $req->loc( 'Exception Handler', $opts ), };

   $e->class eq ValidationErrors->() and $page->{validation_error} = $e->args;

   my $stash = $self->get_stash( $req, $page );

   $stash->{code} = $e->rv >= HTTP_OK ? $e->rv : HTTP_BAD_REQUEST;

   return $stash;
}

sub execute {
   my ($self, $method, @args) = @_;

   $self->can( $method ) and return $self->$method( @args );

   throw 'Class [_1] has no method [_2]', [ blessed $self, $method ];
}

sub get_stash {
   my ($self, $req, $page) = @_;

   my $stash = $self->initialise_stash( $req );

   $stash->{page} = $self->load_page( $req, $page );

   return $stash;
}

sub initialise_stash {
   return { code => HTTP_OK, view => $_[ 0 ]->config->default_view, };
}

sub load_page {
   my ($self, $req, $page) = @_; $page //= {}; return $page;
}

sub not_found : Role(anon) {
   my ($self, $req) = @_;

  (my $mp   = $self->config->mount_point) =~ s{ \A / \z }{}mx;
   my $want = join '/', $mp, $req->path;
   my $e    = exception 'URI [_1] not found', [ $want ], rv => HTTP_NOT_FOUND;

   return $self->exception_handler( $req, $e );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model;
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
