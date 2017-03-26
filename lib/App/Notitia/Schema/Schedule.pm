package App::Notitia::Schema::Schedule;

use strictures;
use parent 'App::Notitia::Schema::Base';

use App::Notitia; our $VERSION = App::Notitia->schema_version;

__PACKAGE__->load_namespaces;

__PACKAGE__->load_components( qw( Schema::Versioned ) );

sub deploy {
   my ($self, @args) = @_;

   eval {
      $self->storage->_get_dbh->do( 'DROP TABLE dbix_class_schema_versions' );
   };

   return $self->next::method( @args );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule;
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
