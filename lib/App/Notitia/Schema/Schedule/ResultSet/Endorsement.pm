package App::Notitia::Schema::Schedule::ResultSet::Endorsement;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );

# Private methods
my $_find_recipient = sub {
   my ($self, $scode) = @_; my $schema = $self->result_source->schema;

   my $opts = { columns => [ 'id' ] };

   return $schema->resultset( 'Person' )->find_by_shortcode( $scode, $opts );
};

# Public methods
sub new_result {
   my ($self, $columns) = @_;

   my $scode = delete $columns->{recipient};

   $scode and $columns->{recipient_id} = $self->$_find_recipient( $scode )->id;

   return $self->next::method( $columns );
}

sub find_endorsement_by {
   my ($self, $scode, $uri) = @_;

   my $endorsement = $self->search
      ( { 'recipient.shortcode' => $scode, uri => $uri },
        { join => [ 'recipient' ] } )->single;

   defined $endorsement
        or throw 'Endorsement [_1] for [_2] not found', [ $uri, $scode ],
                 level => 2;

   return $endorsement;
};

sub search_for_endorsements {
   my ($self, $scode) = @_;

   return $self->search
      ( { 'recipient.shortcode' => $scode },
        { join => [ 'recipient' ], order_by => 'type_code' } );
}

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
