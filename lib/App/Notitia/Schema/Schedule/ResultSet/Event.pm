package App::Notitia::Schema::Schedule::ResultSet::Event;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );

# Private functions
my $_event_tuple = sub {
   my ($event, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{selected} //= NUL;
   $opts->{selected}   = $opts->{selected} eq $event ? TRUE : FALSE;

   return [ $event->label, $event, $opts ];
};

# Private methods
my $_find_owner = sub {
   return $_[ 0 ]->result_source->schema->resultset( 'Person' )->search
      ( { name => $_[ 1 ] }, { columns => [ 'id' ] } )->single;
};

my $_find_rota = sub {
   return $_[ 0 ]->result_source->schema->resultset( 'Rota' )->find_rota
      (   $_[ 1 ], $_[ 2 ] );
};

# Public methods
sub new_result {
   my ($self, $columns) = @_;

   my $name = delete $columns->{rota}; my $date = delete $columns->{date};

   $name and $date
         and $columns->{rota_id} = $self->$_find_rota( $name, $date )->id;

   my $owner = delete $columns->{owner};

   $owner and $columns->{owner_id} = $self->$_find_owner( $owner )->id;

   return $self->next::method( $columns );
}

sub find_event_by {
   my ($self, $name, $date, $opts) = @_; $opts //= {};

   $opts->{prefetch} //= []; push @{ $opts->{prefetch} }, 'rota';

   my $event = $self->search
      ( { 'me.name' => $name, 'rota.date' => $date }, $opts )->single
      or throw 'Event [_1] on [_2] unknown', [ $name, $date ],
         level => 2, rv => HTTP_EXPECTATION_FAILED;

   return $event;
}

sub list_all_events {
   my ($self, $opts) = @_; $opts = { %{ $opts // {} } };

   my $fields = delete $opts->{fields} // {};
   my $events = $self->search
      ( {}, { columns => [ 'name' ], prefetch => [ 'rota' ], %{ $opts } } );

   return [ map { $_event_tuple->( $_, $fields ) } $events->all ];
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Event - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Event;
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
