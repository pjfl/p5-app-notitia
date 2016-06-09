package App::Notitia::Schema::Schedule::Result::Job;

use strictures;
use parent 'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( TRUE );
use App::Notitia::Util      qw( serial_data_type varchar_data_type );
use Class::Usul::IPC;

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'job' );

$class->add_columns
   ( id      => serial_data_type,
     name    => varchar_data_type(   32 ),
     command => varchar_data_type( 1024 ), );

$class->set_primary_key( 'id' );

my $_ipc_obj;

my $_ipc = sub {
   my $self = shift; defined $_ipc_obj and return $_ipc_obj;
   my $app  = $self->result_source->schema->application;

   return $_ipc_obj = Class::Usul::IPC->new( builder => $app );
};

sub insert {
   my $self = shift;
   my $job  = $self->next::method;
   my $conf = $self->result_source->schema->config;
   my $cmd  = $conf->binsdir->catfile( 'notitia-schema' );

   $self->$_ipc->run_cmd( [ $cmd, '-q', 'runqueue' ], { async => TRUE } );

   return $job;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Job - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Job;
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
