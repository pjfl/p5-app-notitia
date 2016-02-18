package App::Notitia::Model::Schedule;

#use App::Notitia::Attributes;  # Will do namespace cleaning
use Class::Usul::Types qw( LoadableClass Object );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
#with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(Web::Components::Role::Forms);

# Attribute constructors
my $_build_schema = sub {
   my $self = shift; my $extra = $self->config->connect_params;

   $self->schema_class->config( $self->config );

   return $self->schema_class->connect( @{ $self->connect_info }, $extra );
};

my $_build_schema_class = sub {
   return $_[ 0 ]->schema_classes->{ $_[ 0 ]->config->database };
};

# Public attributes
has '+moniker'     => default => 'sched';

has 'schema'       => is => 'lazy', isa => Object,
   builder         => $_build_schema;

has 'schema_class' => is => 'lazy', isa => LoadableClass,
   builder         => $_build_schema_class;

around 'load_page' => sub {
   my ($orig, $self, $req, $page, @args) = @_;

   $page = $orig->( $self, $req, $page, @args);

   $page->{template} = [ 'nav_panel', 'rota' ];
   $page->{title   } = $req->loc( 'Rotas' );
   return $page;
};

sub get_content {
   my ($self, $req) = @_; return $self->get_stash( $req );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Schedule - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Schedule;
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
