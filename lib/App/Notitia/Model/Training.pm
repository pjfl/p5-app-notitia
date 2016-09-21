package App::Notitia::Model::Training;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SPC TRUE );
use App::Notitia::Form      qw( blank_form f_link f_tag p_button p_container
                                p_list p_row p_select p_table p_textfield );
use App::Notitia::Util      qw( js_server_config js_submit_config
                                locm make_tip register_action_paths
                                to_dt to_msg uri_for_action );
use Class::Usul::Functions  qw( is_arrayref is_member throw );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'train';

register_action_paths
   'train/summary' => 'training-summary',
   'train/training' => 'training';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_subtract = sub {
   return [ grep { is_arrayref $_ or not is_member $_, $_[ 1 ] } @{ $_[ 0 ] } ];
};

# Private methods
my $_list_all_courses = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ $type_rs->search_for_course_types->all ];
};

# Public methods
sub add_course_action : Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person = $person_rs->find_by_shortcode( $scode );
   my $courses = $req->body_params->( 'courses', { multiple => TRUE } );

   for my $course (@{ $courses }) {
      $person->add_course( $course );

      my $message = 'user:'.$req->username.' client:'.$req->address.SPC
                  . "action:addcourse shortcode:${scode} course:${course}";

      get_logger( 'activity' )->log( $message );
   }

   my $message = [ to_msg '[_1] enroled on course(s): [_2]',
                   $person->label, join ', ', @{ $courses } ];
   my $location = uri_for_action $req, $self->moniker.'/training', [ $scode ];

   return { redirect => { location => $location, message => $message } };
}

sub summary : Role(training_manager) {
   my ($self, $req) = @_;

   my $form = blank_form;
   my $page = {
      forms => [ $form ],
      selected => 'summary',
      title => locm $req, 'training_summary_title'
   };

   return $self->get_stash( $req, $page );
}

sub training : Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person = $person_rs->find_by_shortcode( $scode );
   my $href = uri_for_action $req, $self->moniker.'/training', [ $scode ];
   my $form = blank_form 'training', $href;
   my $page = {
      forms => [ $form ],
      selected => 'summary',
      title => locm $req, 'training_enrolement_title'
      };
   my $courses_taken = $person->list_courses;
   my $courses = $_subtract->( $self->$_list_all_courses, $courses_taken );

   p_textfield $form, 'username', $person->label, { disabled => TRUE };

   p_select $form, 'courses_taken', $courses_taken, {
      multiple => TRUE, size => 5 };

   p_button $form, 'remove_course', 'remove_course', {
      class => 'delete-button', container_class => 'right-last',
      tip => make_tip $req, 'remove_course_tip', [ 'course', $person->label ] };

   p_container $form, f_tag( 'hr' ), { class => 'form-separator' };

   p_select $form, 'courses', $courses, { multiple => TRUE, size => 5 };

   p_button $form, 'add_course', 'add_course', {
      class => 'save-button', container_class => 'right-last',
      tip => make_tip $req, 'add_course_tip', [ 'course', $person->label ] };

   return $self->get_stash( $req, $page );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Training - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Training;
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
