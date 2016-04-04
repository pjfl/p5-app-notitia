package App::Notitia::Schema;

use namespace::autoclean;

use App::Notitia;
use App::Notitia::Constants qw( OK SLOT_TYPE_ENUM TRUE );
use Moo;

extends q(Class::Usul::Schema);
with    q(App::Notitia::Role::Schema);

our $VERSION = $App::Notitia::VERSION;

my $_build_schema_version = sub {
   my ($major, $minor) = $VERSION =~ m{ (\d+) \. (\d+) }mx;

   # TODO: This will break when major number bumps
   return $major.'.'.($minor + 1);
};

# Public attributes (override defaults in base class)
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

# Public methods
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

=head2 C<dump_connect_attr> - Displays database connection information

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
