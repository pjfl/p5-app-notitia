package App::Notitia::Role::UserTable;

use namespace::autoclean;

use Class::Usul::Types qw( ArrayRef LoadableClass NonEmptySimpleStr Object );
use Moo::Role;

requires qw( config get_connect_info );

# Attribute constructors
my $_build_schema = sub {
   my $self   = shift;
   my $schema = $self->table_schema_class->connect
      ( @{ $self->table_schema_connect_attr } );

   $schema->can( 'accept_context' ) and $schema->accept_context( $self );

   return $schema;
};

my $_build_schema_connect_attr = sub {
   my $self  = shift;
   my $extra = $self->config->connect_attr;
   my $opts  = { database => $self->table_schema_database };
   my $info  = $self->get_connect_info( $self, $opts );

   return [ @{ $info }[ 0 .. 2 ], { %{ $extra }, %{ $info->[ 3 ] } } ];
};

# Public attributes
has 'table_schema' => is => 'lazy', isa => Object, builder => $_build_schema;

has 'table_schema_class' => is => 'lazy', isa => LoadableClass, builder => sub {
   $_[ 0 ]->config->schema_classes->{ $_[ 0 ]->table_schema_database } };

has 'table_schema_connect_attr' => is => 'lazy', isa => ArrayRef,
   builder => $_build_schema_connect_attr;

has 'table_schema_database' => is => 'lazy', isa => NonEmptySimpleStr,
   builder => sub { 'usertable' };

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::UserTable - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::UserTable;
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
