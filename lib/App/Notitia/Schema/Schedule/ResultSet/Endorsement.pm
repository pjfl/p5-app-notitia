package App::Notitia::Schema::Schedule::ResultSet::Endorsement;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );

# Private class attributes

# Private methods
my $_find_recipient_id = sub {
   my ($self, $name) = @_;

   my $recipient = $self->result_source->schema->resultset( 'Person' )->search
      ( { name => $name }, { columns => [ 'id' ] } )->single;

   return $recipient->id;
};

# Public methods
sub new_result {
   my ($self, $columns) = @_;

   my $name = delete $columns->{recipient};

   $name and $columns->{recipient_id} = $self->$_find_recipient_id( $name );

   return $self->next::method( $columns );
}

sub find_endorsement_by {
   my ($self, $name, $code) = @_;

   my $endorsement = $self->search
      ( { 'recipient.name' => $name, code => $code },
        { join => [ 'recipient' ] } )->single
        or throw 'Endorsement [_1] for [_2] not found', [ $code, $name ],
                 level => 2, rv => HTTP_EXPECTATION_FAILED;

   return $endorsement;
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Endorsement - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Endorsement;
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
