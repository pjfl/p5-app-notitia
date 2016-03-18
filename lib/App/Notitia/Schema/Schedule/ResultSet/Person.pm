package App::Notitia::Schema::Schedule::ResultSet::Person;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use Class::Usul::Functions  qw( throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );

# Private functions
my $_person_tuple = sub {
   my ($person, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{selected} //= NUL;
   $opts->{selected}   = $opts->{selected} eq $person ? TRUE : FALSE;

   return [ $person->label, $person, $opts ];
};

# Private methods
my $_find_role_type = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_role_by( $name );
};

# Public methods
sub find_person_by {
   my ($self, $name) = @_;

   my $person = $self->search( { name => $name } )->single
      or throw 'Person [_1] unknown', [ $name ], level => 2,
               rv => HTTP_EXPECTATION_FAILED;

   return $person;
}

sub is_person {
   my ($self, $name, $cache) = @_;

   unless ($cache->{people}) {
      for my $person (map { $_->[ 1 ] } @{ $self->list_all_people }) {
         $cache->{people}->{ $person->name } = TRUE;
      }
   }

   return exists $cache->{people}->{ $name } ? TRUE : FALSE;
}

sub list_all_people {
   my ($self, $opts) = @_; $opts = { %{ $opts // {} } };

   my $where  = delete $opts->{current}
              ? { resigned => { '=' => undef } } : {};
   my $fields = delete $opts->{fields} // {};
   my $people = $self->search
      ( $where, { columns => [ 'first_name', 'id', 'last_name', 'name' ],
                  %{ $opts } } );

   return [ map { $_person_tuple->( $_, $fields ) } $people->all ];
}

sub list_participents {
   my ($self, $event, $opts) = @_; $opts = { %{ $opts // {} } };

   my $fields = delete $opts->{fields} // {};
   my $people = $self->search
      ( { 'participents.event_id' => $event->id },
        { columns  => [ 'first_name', 'id', 'last_name', 'name' ],
          join     => [ 'participents' ], %{ $opts } } );

   return [ map { $_person_tuple->( $_, $fields ) } $people->all ];
}

sub list_people {
   my ($self, $role, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{prefetch} = [ 'roles' ];

   my $people = $self->list_all_people( $opts );
   my $type   = $self->$_find_role_type( $role );

   return [ grep { $_->[ 1 ]->is_member_of( $role, $type ) } @{ $people } ];
}

sub new_person_id {
   my ($self, $first_name, $last_name) = @_; my $cache = {}; my $lid;

   my $conf = $self->result_source->schema->config;
   my $name = lc "${last_name}${first_name}"; $name =~ s{ [ \-\'] }{}gmx;

   if ((length $name) < $conf->min_name_length) {
      throw 'Person name [_1] too short [_2] character min.',
            [ $first_name.SPC.$last_name, $conf->min_name_length ];
   }

   my $min_id_len = $conf->min_id_length;
   my $prefix     = $conf->person_prefix; $prefix or return;
   my $lastp      = length $name < $min_id_len ? length $name : $min_id_len;
   my @chars      = (); $chars[ $_ ] = $_ for (0 .. $lastp - 1);

   while ($chars[ $lastp - 1 ] < length $name) {
      my $i = 0; $lid = NUL;

      while ($i < $lastp) { $lid .= substr $name, $chars[ $i++ ], 1 }

      $self->is_person( $prefix.$lid, $cache ) or last;

      $i = $lastp - 1; $chars[ $i ] += 1;

      while ($i >= 0 and $chars[ $i ] >= length $name) {
         my $ripple = $i - 1; $chars[ $ripple ] += 1;

         while ($ripple < $lastp) {
            my $carry = $ripple + 1; $chars[ $carry ] = $chars[ $ripple++ ] + 1;
         }

         $i--;
      }
   }

   $chars[ $lastp - 1 ] >= length $name
       and throw 'Person name [_1] no ids left', [ $first_name.SPC.$last_name ];
   $lid or throw 'Person name [_1] no id', [ $name ];
   return $prefix.$lid;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Person - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Person;
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
