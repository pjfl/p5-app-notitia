package App::Notitia::Role::PageConfiguration;

use namespace::autoclean;

use App::Notitia::Constants qw( TRUE );
use App::Notitia::Util      qw( loc uri_for_action );
use Try::Tiny;
use Moo::Role;

requires qw( config initialise_stash load_page log );

# Construction
around 'initialise_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash  = $orig->( $self, $req, @args ); my $conf = $self->config;

   my $params = $req->query_params; my $sess = $req->session;

   for my $k (@{ $conf->stash_attr->{session} }) {
      try {
         my $v = $params->( $k, { optional => 1 } );

         $stash->{prefs}->{ $k } = defined $v ? $sess->$k( $v ) : $sess->$k();
      }
      catch { $self->log->warn( $_ ) };
   }

   $stash->{skin} = delete $stash->{prefs}->{skin};

   my $links = $stash->{links} //= {};

   for my $k (@{ $conf->stash_attr->{links} }) {
      $links->{ $k } = $req->uri_for( $conf->$k().'/' );
   }

   $links->{cdnjs   } = $conf->cdnjs;
   $links->{base_uri} = $req->base;
   $links->{req_uri } = $req->uri;

   return $stash;
};

around 'load_page' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $page = $orig->( $self, $req, @args ); my $conf = $self->config;

   for my $k (@{ $conf->stash_attr->{request} }) { $page->{ $k }   = $req->$k  }

   for my $k (@{ $conf->stash_attr->{config } }) { $page->{ $k } //= $conf->$k }

   $page->{application_version} = $conf->appclass->VERSION;
   $page->{status_message     } = $req->session->collect_status_message( $req );

   $page->{hint  } //= loc( $req, 'Hint' );
   $page->{wanted} //=
      join '/', @{ $req->uri_params->( { optional => TRUE } ) // [] };

   my $js = $page->{literal_js} //= []; my ($href, $title);

   if ($req->authenticated) {
      $href  = uri_for_action $req, 'user/profile';
      $title = loc $req, 'Person Profile';

      push @{ $js }, $self->dialog_anchor( 'profile-user', $href, {
         name => 'profile-user', title => $title, useIcon => \1 } );
   }
   else {
      $href  = uri_for_action $req, 'user/reset';
      $title = loc $req, 'Reset Password';

      push @{ $js }, $self->dialog_anchor( 'request-reset', $href, {
         name => 'request-reset', title => $title, useIcon => \1 } );
   }

   return $page;
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::PageConfiguration - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::PageConfiguration;
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
