package App::Notitia::Model::Training;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SPC TRAINING_STATUS_ENUM TRUE );
use App::Notitia::Form      qw( blank_form f_tag p_button p_container p_date
                                p_link p_row p_select p_table p_textfield );
use App::Notitia::Util      qw( dialog_anchor locm make_tip
                                register_action_paths to_dt to_msg
                                uri_for_action );
use Class::Usul::Functions  qw( is_arrayref is_member throw );
use Class::Usul::Log        qw( get_logger );
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
   'train/dialog' => 'training-dialog',
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
my $_local_dt = sub {
   return $_[ 0 ]->clone->set_time_zone( 'local' );
};

my $_subtract = sub {
   return [ grep { is_arrayref $_ or not is_member $_, $_[ 1 ] } @{ $_[ 0 ] } ];
};

# Private methods
my $_find_course_type = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_course_by( $_[ 1 ] );
};

my $_find_course = sub {
   my ($self, $req, $scode, $course_name) = @_;

   my $person_rs = $self->schema->resultset( 'Person' );
   my $person = $person_rs->find_by_shortcode( $scode );
   my $course_type = $self->$_find_course_type( $course_name );
   my $course_rs = $self->schema->resultset( 'Training' );

   return $course_rs->find( $person->id, $course_type->id ), $person;
};

my $_list_all_courses = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ $type_rs->search_for_course_types->all ];
};

my $_list_courses = sub {
   my $self = shift;
   my $rs = $self->schema->resultset( 'Training' );
   my $prefetch = [ 'recipient', 'course_type' ];
   my %courses = ();
   my @courses = ();

   for my $course ($rs->search( {}, { prefetch => $prefetch } )->all) {
      my $person = $course->recipient;
      my $index = $courses{ $person->shortcode } //= scalar @courses;

      $courses[ $index ] //= [ $person, {} ];
      $courses[ $index ]->[ 1 ]->{ $course->course_type } = $course;
   }

   return \@courses;
};

my $_summary_cell_js = sub {
   my ($page, $id, $href, $title) = @_;

   push @{ $page->{literal_js} }, dialog_anchor( $id, $href, {
      name => $id, title => $title, useIcon => \1 } );

   return;
};

my $_summary_cell = sub {
   my ($self, $req, $page, $all_courses, $tuple, $index) = @_;

   exists $tuple->[ 1 ]->{ $all_courses->[ $index ] } or return {};

   my $scode = $tuple->[ 0 ]->shortcode;
   my $course = $tuple->[ 1 ]->{ $all_courses->[ $index ] };
   my $status = $course->status;
   my $date = $_local_dt->( $course->$status() )->dmy( '/' );
   my $course_type = $course->course_type;
   my $actionp = $self->moniker.'/dialog';
   my $href = uri_for_action $req, $actionp, [ $scode, $course_type ];
   my $id = "${scode}_${course_type}";
   my $form = blank_form $id, $href, {
      class => 'spreadsheet-fixed-form align-center' };
   my $colours = { completed => 'green', enroled => 'blue',
                   expired => 'red', started => 'yellow' };
   my $title = locm $req, '[_1] Training For [_2]',
                    locm( $req, $course_type ), $tuple->[ 0 ]->label;

   p_link $form, $id, '#', {
      class => 'windows', label => NUL, request => $req, value => $date };

   $_summary_cell_js->( $page, $id, $href, $title );

   return { class => 'spreadsheet-fixed-date',
            style => 'background-color: '.$colours->{ $status },
            value => $form };
};

my $_summary_headers = sub {
   my ($self, $req, $all_courses) = @_;

   return [ { value => locm $req, 'training_header_0' },
            map { { value => locm $req, $_ } } @{ $all_courses } ];
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

sub remove_course_action : Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person = $person_rs->find_by_shortcode( $scode );
   my $courses = $req->body_params->( 'courses_taken', { multiple => TRUE } );

   for my $course (@{ $courses }) {
      $person->delete_course( $course );

      my $message = 'user:'.$req->username.' client:'.$req->address.SPC
                  . "action:removecourse shortcode:${scode} course:${course}";

      get_logger( 'activity' )->log( $message );
   }

   my $message = [ to_msg '[_1] removed from course(s): [_2]',
                   $person->label, join ', ', @{ $courses } ];
   my $location = uri_for_action $req, $self->moniker.'/training', [ $scode ];

   return { redirect => { location => $location, message => $message } };
}

sub dialog : Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $course_name = $req->uri_params->( 1 );
   my ($course) = $self->$_find_course( $req, $scode, $course_name );
   my $stash = $self->dialog_stash( $req );
   my $actionp = $self->moniker.'/training';
   my $href = uri_for_action $req, $actionp, [ $scode, $course_name ];
   my $form = $stash->{page}->{forms}->[ 0 ]
            = blank_form 'user-training', $href, { class => 'dialog-form' };

   for my $status (@{ TRAINING_STATUS_ENUM() }) {
      my $date = $course->$status() // NUL;

      $date and $date = $_local_dt->( $date )->dmy( '/' );

      p_date $form, "${course_name}_${status}_date", $date, {
         class => 'narrow-field',
         disabled => $status eq 'enroled' ? TRUE : FALSE,
         label => "${status}_date", label_class => 'right-last' };
   }

   p_button $form, 'update', 'update_training', { class => 'button right-last'};

   return $stash;
}

sub summary : Role(training_manager) {
   my ($self, $req) = @_;

   my $form = blank_form;
   my $page = {
      forms => [ $form ],
      selected => 'summary',
      title => locm $req, 'training_summary_title'
   };
   my $all_courses = $self->$_list_all_courses;
   my $table = p_table $form, {
      headers => $self->$_summary_headers( $req, $all_courses ) };

   for my $tuple (@{ $self->$_list_courses }) {
      p_row $table,
         [ { value => $tuple->[ 0 ]->label },
       map { $self->$_summary_cell( $req, $page, $all_courses, $tuple, $_ ) }
           0 .. (scalar @{ $all_courses }) - 1 ];
   }

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

sub update_training_action : Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $course_name = $req->uri_params->( 1 );
   my ($course, $person) = $self->$_find_course( $req, $scode, $course_name );
   my $prev = [];

   for my $status (@{ TRAINING_STATUS_ENUM() }) {
      my $date = $req->body_params->( "${course_name}_${status}_date",
                                      { optional => TRUE} ) // NUL;

      $prev->[ 0 ] or ($prev = [ $status, $course->$status() ] and next);

      $date and $date = to_dt $date;
      $date and not $prev->[ 1 ]
            and throw 'Cannot skip [_1] state', [ $prev->[ 0 ] ];
      $date and $date < $prev->[ 1 ]
            and throw '[_1] date cannot be before the [_2] date',
                      { args => [ ucfirst $status, $prev->[ 0 ] ],
                        no_quote_bind_values => TRUE };
      $date and $course->status( $status ) and $course->$status( $date );
      $prev = [ $status, $date ];
   }

   $course->update;

   my $who = $req->session->user_label;
   my $message = [ to_msg 'Training for [_1] updated by [_2]',
                   $person->label, $who ];

   return { redirect => { message => $message} }; # location referer
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
