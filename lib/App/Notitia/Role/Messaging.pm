package App::Notitia::Role::Messaging;

use namespace::autoclean;

use App::Notitia::Constants qw( NUL SPC TRUE );
use App::Notitia::Util      qw( bind button dialog_anchor loc
                                table_link uri_for_action );
use Moo::Role;

requires qw( config dialog_stash moniker );

# Private functions
my $_confirm_mailshot_button = sub {
   return button $_[ 0 ],
      { class => 'right-last', label => 'confirm', value => 'mailshot_create' };
};

my $_flatten = sub {
   my $params = shift; my $r = NUL;

   for my $k (keys %{ $params }) { $r .= "-o ${k}=".$params->{ $k }.' ' }

   return $r;
};

# Private methods
my $_list_mailshot_templates = sub {
   my $self   = shift;
   my $dir    = $self->config->assetdir->clone;
   my $plates = $dir->filter( sub { m{ \.tt \z }mx } );

   return [ map { [ $_->basename( '.tt' ), "${_}" ] } $plates->all_files ];
};

# Public methods
sub mailshot_create {
   my ($self, $req, $opts) = @_;

   my $params   = $req->query_params->( { optional => TRUE } ) // {};

   delete $params->{mid};

   my $conf     = $self->config;
   my $template = $req->body_params->( 'template' );
   my $job_rs   = $self->schema->resultset( 'Job' );
   my $cmd      = $conf->binsdir->catfile( 'notitia-schema' ).SPC
                . $_flatten->( $params )."mailshot ${template}";
   my $job      = $job_rs->create( { command => $cmd, name => 'mailshot' } );
   my $message  = [ 'Job mailshot-[_1] created', $job->id ];
   my $location = uri_for_action $req, $self->moniker.'/'.$opts->{action};

   return { redirect => { location => $location, message => $message } };
}

sub mailshot_link {
   my ($self, $req, $page, $actionp, $params) = @_;

   $params = { %{ $params // {} } };

   my $name = delete $params->{name};
   my $href = uri_for_action $req, $actionp, [], $params;

   push @{ $page->{literal_js} //= [] },
      dialog_anchor( 'mailshot', $href, {
         name    => $name,
         title   => loc( $req, 'Send email to people' ),
         useIcon => \1 } );

   return table_link $req, 'mailshot', loc( $req, 'mailshot_management_link' ),
                                       loc( $req, 'mailshot_management_tip' );
}

sub mailshot_stash {
   my ($self, $req, $opts) = @_;

   my $params    = $req->query_params->( { optional => TRUE } ) // {};
   my $stash     = $self->dialog_stash( $req, $opts->{layout} );
   my $actionp   = $self->moniker.'/'.$opts->{action};
   my $templates = $self->$_list_mailshot_templates;
   my $fields    = $stash->{page}->{fields};

   delete $params->{id}; delete $params->{val};
   $fields->{confirm } = $_confirm_mailshot_button->( $req );
   $fields->{href    } = uri_for_action $req, $actionp, [], $params;
   $fields->{template} = bind 'template', [ [ NUL, NUL ], @{ $templates } ];

   return $stash;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::Messaging - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::Messaging;
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
