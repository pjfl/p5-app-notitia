package App::Notitia::Schema;

use namespace::autoclean;

use App::Notitia;
use App::Notitia::Constants qw( OK TRUE );
use Class::Usul::Types      qw( LoadableClass Object );
use Moo;

extends q(Class::Usul::Schema);

our $VERSION         = $App::Notitia::VERSION;
my ($schema_version) = $VERSION =~ m{ (\d+\.\d+) }mx;

# Attribute constructors
my $_build_schedule = sub {
   my $self = shift; my $extra = $self->config->connect_params;

   $self->schedule_class->config( $self->config );

   return $self->schedule_class->connect( @{ $self->connect_info }, $extra );
};

my $_build_schedule_class = sub {
   return $_[ 0 ]->schema_classes->{ $_[ 0 ]->config->database };
};

# Public attributes (override defaults in base class)
has '+config_class'   => default => 'App::Notitia::Config';

has '+database'       => default => sub { $_[ 0 ]->config->database };

has '+schema_classes' => default => sub { $_[ 0 ]->config->schema_classes };

has '+schema_version' => default => $schema_version;

has 'schedule'        => is => 'lazy', isa => Object,
   builder            => $_build_schedule;

has 'schedule_class'  => is => 'lazy', isa => LoadableClass,
   builder            => $_build_schedule_class;

# Construction
around 'deploy_file' => sub {
   my ($orig, $self, @args) = @_;

   $self->config->appclass->env_var( 'buld_insert', TRUE );

   return $orig->( $self, @args );
};

# Public methods
sub display_connect_info : method {
   my $self = shift; $self->dumper( $self->connect_info ); return OK;
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

=head2 C<display_connect_info> - Displays database connection information

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
