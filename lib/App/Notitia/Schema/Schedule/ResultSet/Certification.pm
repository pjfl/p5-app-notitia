package App::Notitia::Schema::Schedule::ResultSet::Certification;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );

# Private methods
my $_find_recipient = sub {
   return $_[ 0 ]->result_source->schema->resultset( 'Person' )->search
      ( { name => $_[ 1 ] }, { columns => [ 'id' ] } )->single;
};

my $_find_cert_type_id = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_certification_by( $name )->id;
};

# Public methods
sub new_result {
   my ($self, $columns) = @_;

   my $name = delete $columns->{recipient};

   $name and $columns->{recipient_id} = $self->$_find_recipient( $name )->id;

   my $type = delete $columns->{type};

   $type and $columns->{type_id} = $self->$_find_cert_type_id( $type );

   return $self->next::method( $columns );
}

sub find_cert_by {
   my ($self, $name, $type) = @_;

   my $cert = $self->search
      ( { 'recipient.name' => $name, 'type.name' => $type },
        { join => [ 'recipient', 'type' ] } )->single
        or throw 'Certification [_1] for [_2] not found', [ $type, $name ],
                 level => 2, rv => HTTP_EXPECTATION_FAILED;

   return $cert;
};

sub list_certification_for {
   my ($self, $req, $name) = @_;

   my $certs = $self->search
      ( { 'recipient.name' => $name },
        { join     => [ 'recipient', 'type' ], order_by => 'type_class',
          prefetch => [ 'type' ] } );

   return [ map { [ $_->label( $req ), $_ ] } $certs->all ];
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Certification - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Certification;
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
