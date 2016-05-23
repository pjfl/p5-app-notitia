package App::Notitia::Schema::Schedule::ResultSet::Rota;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Util qw( to_dt );
use Scalar::Util qw( blessed );

# Public methods
sub find_rota {
   my ($self, $name, $date) = @_;

   blessed $date or $date = to_dt $date;

   my $schema     =  $self->result_source->schema;
   my $rota_type  =  $schema->resultset( 'Type' )->find_rota_by( $name );
   my $rota       =  $self->search
      ( { date    => $schema->datetime_parser->format_datetime( $date ),
          type_id => $rota_type->id } )->single;

   $rota or $rota =  $self->create
      ( { date    => $date, type_id => $rota_type->id } );

   return $rota;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Rota - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Rota;
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
