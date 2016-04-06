package App::Notitia::Schema::Base;

use strictures;
use parent 'DBIx::Class::Core';

use App::Notitia::Constants qw( NUL TRUE );
use App::Notitia::Util      qw( assert_unique );
use Data::Validation;

__PACKAGE__->load_components( qw( InflateColumn::Object::Enum TimeStamp ) );

sub find_shift {
   my ($self, $rota_name, $date, $shift_type) = @_;

   my $schema = $self->result_source->schema;
   my $rota   = $schema->resultset( 'Rota' )->find_rota( $rota_name, $date );

   return $schema->resultset( 'Shift' )->find_or_create
      ( { rota_id => $rota->id, type_name => $shift_type } );
}

sub find_slot {
   my ($self, $shift, $slot_type, $subslot) = @_;

   my $slot_rs = $self->result_source->schema->resultset( 'Slot' );

   return $slot_rs->find_slot_by( $shift, $slot_type, $subslot );
}

sub validate {
   my $self = shift; my $attr = $self->validation_attributes;

   defined $attr->{fields} or return TRUE;

   my $columns = { $self->get_inflated_columns };
   my $rs      = $self->result_source->resultset;

   for my $field (keys %{ $attr->{fields} }) {
      $attr->{fields}->{ $field }->{unique} and exists $columns->{ $field }
         and assert_unique $rs, $columns, $attr->{fields}, $field;

      my $valids =  $attr->{fields}->{ $field }->{validate} or next;
         $valids =~ m{ isMandatory }msx and $columns->{ $field } //= undef;
   }

   $columns = Data::Validation->new( $attr )->check_form( NUL, $columns );
   $self->set_inflated_columns( $columns );
   return TRUE;
}

sub validation_attributes {
   return {};
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Base - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Base;
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
