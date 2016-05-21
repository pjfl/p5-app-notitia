package App::Notitia::SMS;

use namespace::autoclean;

use Class::Null;
use Class::Usul::Constants qw( FALSE NUL );
use Class::Usul::Functions qw( throw );
use Class::Usul::Time      qw( nap );
use Class::Usul::Types     qw( ArrayRef Bool HashRef Logger NonEmptySimpleStr
                               PositiveInt );
use HTTP::Tiny;
use Moo;

# Public attributes
has 'base_url'     => is => 'ro', isa => NonEmptySimpleStr,
   default         => 'http://www.bulksms.co.uk:5567/eapi';

has 'http_options' => is => 'ro', isa => HashRef, builder => sub { {} };

has 'log'          => is => 'ro', isa => Logger,
   builder         => sub { Class::Null->new };

has 'num_tries'    => is => 'ro', isa => PositiveInt, default => 3;

has 'password'     => is => 'ro', isa => NonEmptySimpleStr;

has 'quote'        => is => 'ro', isa => Bool, default => FALSE;

has 'send_options' => is => 'ro', isa => HashRef, builder => sub { {} };

has 'timeout'      => is => 'ro', isa => PositiveInt, default => 10;

has 'username'     => is => 'ro', isa => NonEmptySimpleStr;

# Private functions
my $_option_keys =
   [ qw( allow_concat_text_sms dca msg_class oncat_text_sms_max_parts
         repliable routing_group scheduling_description send_time
         send_time_unixtime sender source_id stop_dup_id
         strip_dup_recipients test_always_fail test_always_succeed
         want_report ) ];

# Constructions
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   for my $k (@{ $_option_keys }) {
      exists $attr->{ $k }
         and $attr->{send_options}->{ $k } = delete $attr->{ $k };
   }

   return $attr;
};

# Private functions
my $_flatten = sub {
   my $params = shift; my $r = NUL;

   for my $k (keys %{ $params }) { $r .= "${k}=".$params->{ $k }.' ' }

   $r =~ s{ \n }{ }gmx;

   return $r;
};

# Public methods
sub send_sms {
   my ($self, $message, @recipients) = @_;

   $recipients[ 0 ] or throw 'No SMS recipients';

   my $options = { %{ $self->http_options } };
   my $params  = { %{ $self->send_options } };

   $options->{timeout} ||= $self->timeout;
   $params->{message } = $message; $params->{msisdn} = join ',', @recipients;
   $params->{password} = $self->password; $params->{username} = $self->username;

   my $method = $self->quote ? 'quote_sms' : 'send_sms';
   my $url    = $self->base_url."/submission/${method}/2/2.0";
   my $http   = HTTP::Tiny->new( %{ $options } );

   $self->log->debug( "SMS ${url} ".$_flatten->( $params ) );

   my ($code, $desc, $rval);

   for (1 .. $self->num_tries) {
      my $res;

      for (1 .. $self->num_tries) {
         $res = $http->post_form( $url, $params );
         $res->{success} and last; nap 0.25;
      }

      $res->{success} or throw 'SMS transport error [_1]: [_2]',
                         [ $res->{status}, $res->{reason} ];

      ($code, $desc, $rval) = split m{ \| }mx, $res->{content};
      $code == 0 and last; nap 0.25;
   }

   $code == 0 or throw 'SMS send error [_1]: [_2]', [ $code, $desc ];

   return $rval;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::SMS - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::SMS;
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
