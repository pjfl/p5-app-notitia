package App::Notitia::Schema::Schedule::Result::Endorsement;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( TRUE VARCHAR_MAX_SIZE );
use App::Notitia::DataTypes qw( foreign_key_data_type
                                numerical_id_data_type varchar_data_type );
use App::Notitia::Util      qw( local_dt locm );
use Class::Usul::Functions  qw( create_token );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'endorsement' );

$class->add_columns
   ( recipient_id   => foreign_key_data_type,
     points         => numerical_id_data_type,
     endorsed       => {
        data_type   => 'datetime', datetime_undef_if_invalid => TRUE,
        timezone    => 'GMT', },
     type_code      => varchar_data_type( 25 ),
     uri            => varchar_data_type( 32 ),
     notes          => varchar_data_type, );

$class->set_primary_key( 'recipient_id', 'type_code', 'endorsed' );

$class->add_unique_constraint( [ 'uri' ] );

$class->belongs_to( recipient => "${result}::Person", 'recipient_id' );

# Private methods
sub _as_string {
   return $_[ 0 ]->type_code;
}

my $_set_uri = sub {
   my $self     = shift;
   my $columns  = { $self->get_inflated_columns };
   my $recip_id = $columns->{recipient_id};
   my $tcode    = lc $columns->{type_code}; $tcode =~ s{ [ \-] }{_}gmx;
   my $endorsed = local_dt( $columns->{endorsed} )->ymd;
   my $token    = lc substr create_token( $tcode.$recip_id.$endorsed ), 0, 6;

   $columns->{uri} = "${tcode}-${token}";
   $self->set_inflated_columns( $columns );
   return;
};

# Public methods
sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   $self->$_set_uri;

   return $self->next::method;
}

sub label {
   my ($self, $req) = @_;

   my $type = $req ? locm( $req, $self->type_code ) : $self->type_code;

   return $type.' ('.local_dt( $self->endorsed )->dmy( '/' ).')';
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns ); $self->validate;

   $self->$_set_uri;

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints    => {
         type_code   => { max_length => 25, min_length => 4 },
         notes       => { max_length => VARCHAR_MAX_SIZE(), min_length => 0, },
      },
      fields         => {
         endorsed    => { validate => 'isMandatory isValidDate' },
         notes       => { validate => 'isValidLength isValidText' },
         points      => { validate => 'isValidInteger' },
         type_code   => {
            filters  => 'filterTitleCase',
            validate => 'isMandatory isValidLength isSimpleText' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Endorsements - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Endorsements;
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
