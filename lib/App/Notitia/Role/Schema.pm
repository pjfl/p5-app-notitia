package App::Notitia::Role::Schema;

use namespace::autoclean;

use Class::Usul::Types qw( LoadableClass Object );
use Moo::Role;

requires qw( config get_connect_info );

# Attribute constructors
my $_build_schema = sub {
   my $self = shift; my $extra = $self->config->connect_params;

   $self->schema_class->config( $self->config );

   return $self->schema_class->connect( @{ $self->get_connect_info }, $extra );
};

my $_build_schema_class = sub {
   return $_[ 0 ]->config->schema_classes->{ $_[ 0 ]->config->database };
};

# Public attributes
has 'schema'       => is => 'lazy', isa => Object,
   builder         => $_build_schema;

has 'schema_class' => is => 'lazy', isa => LoadableClass,
   builder         => $_build_schema_class;

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::Schema - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::Schema;
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
