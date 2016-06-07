package App::Notitia::Role::Messaging;

use namespace::autoclean;

use App::Notitia::Constants qw( NUL SPC TRUE );
use App::Notitia::Util      qw( bind button js_window_config loc
                                table_link to_msg uri_for_action );
use Class::Usul::File;
use Class::Usul::Functions  qw( create_token throw );
use Moo::Role;

requires qw( config dialog_stash moniker );

# Private functions
my $_confirm_message_button = sub {
   return button $_[ 0 ],
      { class => 'right-last', label => 'confirm', value => 'message_create' };
};

my $_plate_label = sub {
   my $v = ucfirst $_[ 0 ]->basename( '.md' ); $v =~ s{[_\-]}{ }gmx; return $v;
};

# Private methods
my $_flatten = sub {
   my ($self, $req) = @_;

   my $selected = $req->body_params->( 'selected',
                                       { optional => TRUE, multiple => TRUE } );
   my $params   = $req->query_params->( { optional => TRUE } ) // {};
   my $r        = NUL; delete $params->{mid};

   if (defined $selected->[ 0 ]) {
      my $data = { selected => $selected };
      my $key  = substr create_token, 0, 32;
      my $path = $self->config->sessdir->catfile( $key );
      my $opts = { path => $path->assert,
                   data => $data, storage_class => 'JSON' };

      Class::Usul::File->data_dump( $opts ); $r = "-o recipients=${path} ";
   }
   else {
      exists $params->{type} and $params->{type} eq 'contacts'
         and throw 'Messaging all contacts is not allowed';

      for my $k (keys %{ $params }) { $r .= "-o ${k}=".$params->{ $k }.' ' }
   }

   return $r;
};

my $_list_message_templates = sub {
   my ($self, $req) = @_;

   my $conf   = $self->config;
   my $dir    = $conf->docs_root->catdir
      ( $req->locale, $conf->posts, $conf->drafts );
   my $plates = $dir->filter( sub { m{ \.md \z }mx } );

   $dir->exists or return [ [ NUL, NUL ] ];

   return [ map { [ $_plate_label->( $_ ), "${_}" ] } $plates->all_files ];
};

# Public methods
sub message_create {
   my ($self, $req, $opts) = @_;

   my $conf     = $self->config;
   my $sink     = $req->body_params->( 'sink' );
   my $template = $req->body_params->( 'template' );
   my $cmd      = $conf->binsdir->catfile( 'notitia-schema' ).SPC
                . $self->$_flatten( $req )."send_message ${sink} ${template}";
   my $job_rs   = $self->schema->resultset( 'Job' );
   my $job      = $job_rs->create( { command => $cmd, name => 'send_message' });
   my $message  = [ to_msg 'Job send-message-[_1] created', $job->id ];
   my $location = uri_for_action $req, $self->moniker.'/'.$opts->{action};

   return { redirect => { location => $location, message => $message } };
}

sub message_link {
   my ($self, $req, $page, $href, $name) = @_;

   my $opts = {
         name    => $name,
         target  => $page->{form}->{name},
         title   => loc( $req, 'message_title' ),
         useIcon => \1 };

   push @{ $page->{literal_js} //= [] }, js_window_config
      'message', 'click', 'inlineDialog', [ "${href}", $opts ];

   return table_link $req, 'message', loc( $req, 'message_management_link' ),
                                      loc( $req, 'message_management_tip' );
}

sub message_stash {
   my ($self, $req, $opts) = @_;

   my $params    = $req->query_params->( { optional => TRUE } ) // {};
   my $stash     = $self->dialog_stash( $req, $opts->{layout} );
   my $templates = $self->$_list_message_templates( $req );
   my $fields    = $stash->{page}->{fields};
   my $values    = [ [ 'Email', 'email', { selected => TRUE } ],
                     [ 'SMS',   'sms' ] ];

   delete $params->{id}; delete $params->{val};
   $fields->{confirm } = $_confirm_message_button->( $req );
   $fields->{sink    } = bind 'sink', $values, { label => 'Message sink' };
   $fields->{template} = bind 'template', [ [ NUL, NUL ], @{ $templates } ];

   if ($opts->{action}) {
      my $actionp = $self->moniker.'/'.$opts->{action};

      $fields->{href} = uri_for_action $req, $actionp, [], $params;
   }

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
