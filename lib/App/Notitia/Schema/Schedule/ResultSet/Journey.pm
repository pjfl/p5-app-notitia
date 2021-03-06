package App::Notitia::Schema::Schedule::ResultSet::Journey;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( FALSE NUL TRUE );
use App::Notitia::Util      qw( now_dt set_rota_date );

my $_find_by_shortcode = sub {
   my ($self, $scode) = @_;

   my $rs = $self->result_source->schema->resultset( 'Person' );

   return $rs->find_by_shortcode( $scode );
};

sub search_for_journeys {
   my ($self, $opts) = @_; $opts = { %{ $opts // () } };

   my $parser = $self->result_source->schema->datetime_parser;
   my $done = delete $opts->{done} ? TRUE : FALSE;
   my $is_manager = delete $opts->{is_manager} ? TRUE : FALSE;
   my $scode = delete $opts->{controller};
   my $where = { completed => $done };

   set_rota_date $parser, $where, 'requested', $opts;

   if ($done) {
      if (not $is_manager and $scode) {
         my $after = now_dt->subtract( hours => 24 );

         $where->{ 'delivered' }->{ '>' } = $parser->format_datetime( $after );
         $where->{controller_id} = $self->$_find_by_shortcode( $scode )->id;
      }

      $opts->{order_by} //= { -desc => 'delivered' };
   }
   else { $opts->{order_by} //= 'requested' }

   $opts->{prefetch} //= [ 'controller', 'customer' ];

   return $self->search( $where, $opts );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Journey - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Journey;
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
