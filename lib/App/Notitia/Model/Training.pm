package App::Notitia::Model::Training;

use namespace::autoclean;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL SPC TRAINING_STATUS_ENUM TRUE );
use App::Notitia::DOM       qw( new_container f_tag p_button p_cell p_container
                                p_date p_hidden p_item p_js p_link p_list p_row
                                p_select p_table p_textfield );
use App::Notitia::Util      qw( dialog_anchor js_submit_config link_options
                                local_dt locd locm make_tip management_link
                                page_link_set register_action_paths to_dt
                                to_msg );
use Class::Usul::Functions  qw( is_arrayref is_member throw );
use Data::Page;
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
   'train/events' => 'training-courses',
   'train/summary' => 'training-summary',
   'train/training' => 'training';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'events';
   $stash->{navigation}
      //= $self->events_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_events_headers = sub {
   return [ map { { value => locm( $_[ 0 ], "training_events_heading_${_}" ) } }
            0 .. 2 ];
};

my $_onchange_submit = sub {
   my ($page, $k) = @_;

   p_js $page, js_submit_config
      $k, 'change', 'submitForm', [ 'toggle_suppress', 'training-summary' ];

   return;
};

my $_subtract = sub {
   return [ grep { is_arrayref $_ or not is_member $_, $_[ 1 ] } @{ $_[ 0 ] } ];
};

my $_suppress_summary_row = sub {
   my ($all_courses, $tuple) = @_; my $suppress = TRUE;

   for my $index (0 .. (scalar @{ $all_courses }) - 1) {
      my $course = $all_courses->[ $index ];

      exists $tuple->[ 1 ]->{ $course } or next;

      if ($tuple->[ 1 ]->{ $course }->status ne 'completed') {
         $suppress = FALSE; last;
      }
   }

   return $suppress;
};

# Private methods
my $_cell_colours = sub {
   my ($self, $status) = @_;

   my $bg_colours = { completed => 'green', enrolled => 'blue',
                      expired => 'red', started => 'yellow' };
   my $fg_colours = { started => 'black' };

   return $bg_colours->{ $status }, $fg_colours->{ $status };
};

my $_event_links = sub {
   my ($self, $req, $event) = @_; my $links = [];

   my $uri   = $event->uri;
   my $href  = $req->uri_for_action( 'event/training_event', [ $uri ] );
   my $value = $event->localised_label( $req );
   my $cell  = p_cell $links;

   p_link $cell, 'training_event', $href, { value => $value };

   my @actions = qw( event/participants event/event_summary );

   for my $actionp (@actions) {
      p_item $links, management_link $req, $actionp, $uri;
   }

   return $links;
};

my $_summary_caption = sub {
   my ($self, $req) = @_;

   return locm $req, 'training_summary_caption',
      map { "<span style=\"color: ${_};\">${_}</span>" }
      map { my ($colour) = $self->$_cell_colours( $_ ); $colour }
      qw( enrolled started completed expired );
};

my $_enrol_link = sub {
   my ($self, $req, $person, $course_name) = @_;

   my $actp = $self->moniker.'/training';
   my $href = $req->uri_for_action( $actp, [ "${person}" ] );
   my $form = new_container 'training', $href;
   my $text = 'Enroll [_1] on the [_2]';

   $course_name !~ m{ course \z }mx and $text .= ' course';

   my $tip = make_tip $req, $text, [ $person->label, $course_name ];

   p_button $form, 'enrol', 'add_course', {
      class => 'table-link', label => locm( $req, 'Enroll' ), tip => $tip };
   p_hidden $form, 'courses', $course_name;

   $self->add_csrf_token( $req, $form );

   return $form;
};

my $_events_ops_links = sub {
   my ($self, $req, $params, $pager) = @_; my $links = [];

   my $actionp = $self->moniker.'/events';
   my $page_links = page_link_set $req, $actionp, [], $params, $pager;

   $page_links and push @{ $links }, $page_links;

   $actionp = 'event/training_event';

   is_member 'training_manager', $req->session->{roles}
      and p_link $links, 'training_event', $req->uri_for_action( $actionp ), {
         action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

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
   my $self = shift; my %courses = (); my @courses = ();

   my $rs = $self->schema->resultset( 'Training' );
   my $opts = { order_by => [ 'recipient.name' ],
                prefetch => [ 'recipient', 'course_type' ] };

   for my $course ($rs->search( {}, $opts )->all) {
      my $person = $course->recipient;
      my $index = $courses{ $person->shortcode } //= scalar @courses;

      $courses[ $index ] //= [ $person, {} ];
      $courses[ $index ]->[ 1 ]->{ $course->course_type } = $course;
   }

   return @courses;
};

my $_summary_cell_js = sub {
   my ($page, $id, $href, $title) = @_;

   p_js $page, dialog_anchor $id, $href, { title => $title, };

   return;
};

my $_summary_cell = sub {
   my ($self, $req, $page, $all_courses, $tuple, $index) = @_;

   my $person = $tuple->[ 0 ];
   my $course_name = $all_courses->[ $index ];

   exists $tuple->[ 1 ]->{ $course_name }
      or return { value => $self->$_enrol_link( $req, $person, $course_name ) };

   my $scode = $person->shortcode;
   my $course = $tuple->[ 1 ]->{ $course_name };
   my $status = $course->status;
   my $date = locd $req, $course->$status();
   my $course_type = $course->course_type;
   my $actionp = $self->moniker.'/dialog';
   my $href = $req->uri_for_action( $actionp, [ $scode, $course_type ] );
   my $id = "${scode}_${course_type}";
   my $form = new_container $id, $href, {
      class => 'spreadsheet-fixed-form align-center' };
   my $title = locm $req, '[_1] Training For [_2]',
                    locm( $req, $course_type ), $tuple->[ 0 ]->label;
   my $link = { class => 'windows', label => NUL,
                request => $req, tip => "${course_type}_tip", value => $date };
   my ($bg_colour, $fg_colour) = $self->$_cell_colours( $status );

   $fg_colour and $link->{style} = "color: ${fg_colour}";

   p_link $form, $id, '#', $link;

   $_summary_cell_js->( $page, $id, $href, $title );

   return { style => "background-color: ${bg_colour}", value => $form };
};

my $_summary_headers = sub {
   return [ map { { value => locm $_[ 1 ], "${_}_abbrev" } } @{ $_[ 2 ] } ];
};

my $_summary_ops_links = sub {
   my ($self, $req, $page, $max_rows, $opts) = @_;

   my $actionp = $self->moniker.'/summary';
   my $link_opts = { class => 'log-links' };
   my $dp = Data::Page->new( $max_rows, $opts->{rows}, $opts->{page} );
   my $page_links = page_link_set $req, $actionp, [], $opts, $dp, $link_opts;
   my $form = new_container 'training-summary', $req->uri_for_action( $actionp ), {
      class => 'none' };
   my $show_training = $req->session->show_training;
   my $select_opts =
      [ [ 'Hide', FALSE, { selected => $show_training } ],
        [ 'Show', TRUE,  { selected => $show_training } ] ];

   p_select $form, 'show_completed_training', $select_opts, {
      class => 'single-character filter-column submit',
      id => 'show_completed_training', label_class => 'right',
      label_field_class => 'control-label' };

   $_onchange_submit->( $page, 'show_completed_training' );

   my $links = [ $form ]; $page_links and push @{ $links }, $page_links;

   return $links;
};

my $_user_header = sub {
   return [ { value => locm $_[ 1 ], 'training_header_0' } ];
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

      my $message = "action:add-course shortcode:${scode} course:${course}";

      $self->send_event( $req, $message );
   }

   my $message = [ to_msg '[_1] enrolled on course(s): [_2]',
                   $person->label, join ', ', @{ $courses } ];
   my $location = $req->uri_for_action( $self->moniker.'/training', [ $scode ]);

   return { redirect => { message => $message } }; # location referer
}

sub dialog : Dialog Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $course_name = $req->uri_params->( 1 );
   my ($course) = $self->$_find_course( $req, $scode, $course_name );
   my $stash = $self->dialog_stash( $req );
   my $actionp = $self->moniker.'/training';
   my $href = $req->uri_for_action( $actionp, [ $scode, $course_name ] );
   my $form = $stash->{page}->{forms}->[ 0 ]
            = new_container 'user-training', $href, { class => 'dialog-form' };

   for my $status (@{ TRAINING_STATUS_ENUM() }) {
      my $date = $course->$status() // NUL; $date and $date = locd $req, $date;

      p_date $form, "${course_name}_${status}_date", $date, {
         class => 'narrow-field',
         disabled => $status eq 'enrolled' ? TRUE : FALSE,
         label => "${status}_date", label_class => 'right-last' };
   }

   p_button $form, 'update', 'update_training', { class => 'button right-last'};
   p_button $form, 'remove', 'remove_course', { class => 'button right' };
   p_hidden $form, 'courses_taken', $course_name;

   return $stash;
}

sub events : Role(any) {
   my ($self, $req) = @_;

   my $params = $req->query_params->( {
      optional => TRUE } ); delete $params->{mid};
   my $after = $params->{after} ? to_dt( $params->{after} ) : FALSE;
   my $before = $params->{before} ? to_dt( $params->{before} ) : FALSE;
   my $opts = { after      => $after,
                before     => $before,
                event_type => 'training',
                page       => $params->{page} // 1,
                rows       => $req->session->rows_per_page };
   my $event_rs = $self->schema->resultset( 'Event' );
   my $events = $event_rs->search_for_events( $opts );
   my $pager = $events->pager;
   my $form = new_container;
   my $page = {
      forms => [ $form ], selected => 'training_events',
      title => locm $req, 'training_events_title',
   };
   my $page_links = $self->$_events_ops_links( $req, $params, $pager );

   p_list $form, NUL, $page_links, link_options 'right';

   my $table = p_table $form, { headers => $_events_headers->( $req ) };

   p_row $table, [ map { $self->$_event_links( $req, $_ ) } $events->all ];

   return $self->get_stash( $req, $page );
}

sub remove_course_action : Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person = $person_rs->find_by_shortcode( $scode );
   my $courses = $req->body_params->( 'courses_taken', { multiple => TRUE } );

   for my $course (@{ $courses }) {
      $person->delete_course( $course );

      my $message = "action:remove-course shortcode:${scode} course:${course}";

      $self->send_event( $req, $message );
   }

   my $message = [ to_msg '[_1] removed from course(s): [_2]',
                   $person->label, join ', ', @{ $courses } ];
   my $location = $req->uri_for_action( $self->moniker.'/training', [ $scode ]);

   return { redirect => { message => $message } }; # location referer
}

sub summary : Role(training_manager) {
   my ($self, $req) = @_;

   my $params = $req->query_params->( {
      optional => TRUE } ); delete $params->{mid};
   my $opts = { page => delete $params->{page} // 1,
                rows => $req->session->rows_per_page, };
   my $form = new_container;
   my $page = {
      forms => [ $form ], selected => 'training',
      title => locm $req, 'training_summary_title'
   };
   my $all_courses = $self->$_list_all_courses;
   my @courses = $self->$_list_courses;
   my $page_links = $self->$_summary_ops_links
      ( $req, $page, scalar @courses, $opts );
   my $start_row = $opts->{rows} * ($opts->{page} - 1);

   @courses = splice @courses, $start_row, $opts->{rows};
   p_list $form, NUL, $page_links, { class => 'operation-links align-right' };

   my $outer_table = p_table $form, {
      caption => $self->$_summary_caption( $req ) };
   my $user_table = p_table {}, {
      class => 'embeded', headers => $self->$_user_header( $req ) };
   my $course_table = p_table {}, {
      class => 'embeded no-header-wrap',
      headers => $self->$_summary_headers( $req, $all_courses ) };
   my $container = p_container {}, $course_table, { class => 'limited-table' };
   my $suppress = not $req->session->show_training;

   p_row $outer_table, [ { class => 'embeded person-column',
                           value => $user_table },
                         { class => 'embeded', value => $container } ];

   for my $tuple (@courses) {
      $suppress and $_suppress_summary_row->( $all_courses, $tuple ) and next;
      p_row $user_table, [ { value => $tuple->[ 0 ]->label } ];
      p_row $course_table,
        [ map { $self->$_summary_cell( $req, $page, $all_courses, $tuple, $_ ) }
          0 .. (scalar @{ $all_courses }) - 1 ];
   }

   return $self->get_stash( $req, $page );
}

sub toggle_suppress_action : Role(training_manager) {
   my ($self, $req) = @_;

   $req->session->show_training
      ( $req->body_params->( 'show_completed_training' ) );

   my $location = $req->uri_for_action( $self->moniker.'/summary' );

   return { redirect => { location => $location } };
}

sub training : Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $role = $req->query_params->( 'role', { optional => TRUE } );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person = $person_rs->find_by_shortcode( $scode );
   my $href = $req->uri_for_action( $self->moniker.'/training', [ $scode ] );
   my $form = new_container 'training', $href;
   my $page = {
      forms => [ $form ], selected => $role ? "${role}_list" : 'summary',
      location => 'management',
      selected => $role ? "${role}_list" : 'people_list',
      title => locm $req, 'training_enrolment_title'
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

   my $stash = $self->get_stash( $req, $page );

   $stash->{navigation}
      = $self->management_navigation_links( $req, $stash->{page} );

   return $stash;
}

sub update_training_action : Role(training_manager) {
   my ($self, $req) = @_;

   my $scode = $req->uri_params->( 0 );
   my $course_name = $req->uri_params->( 1 );
   my ($course, $person) = $self->$_find_course( $req, $scode, $course_name );
   my $prev = [];

   for my $status (@{ TRAINING_STATUS_ENUM() }) {
      my $key  = "${course_name}_${status}_date";
      my $date = $req->body_params->( $key, { optional => TRUE} ) // NUL;

      $prev->[ 0 ] or
         ($prev = [ $status,
                    local_dt( $course->$status() )->truncate( to => 'day' ) ]
          and next);

      $date or ($prev = [ $status, FALSE ] and next);

      my $local_dt = local_dt( my $dt = to_dt $date ); my $dmy = locd $req, $dt;

      $prev->[ 1 ] or throw 'Cannot skip [_1] state', [ $prev->[ 0 ] ];
      $local_dt < $prev->[ 1 ]
         and throw '[_1] date cannot be before the [_2] date', {
            args => [ ucfirst $status, $prev->[ 0 ] ],
            no_quote_bind_values => TRUE };
      $course->status( $status ); $course->$status( $dt ); $course->update;

      my $message = "action:update-course shortcode:${scode} "
                  . "course:${course_name} date:${dmy} status:${status}";

      $self->send_event( $req, $message );
      $prev = [ $status, $local_dt->truncate( to => 'day' ) ];
   }

   my $key = 'Training for [_1] updated by [_2]';
   my $message = [ to_msg $key, $person->label, $req->session->user_label ];

   return { redirect => { message => $message } }; # location referer
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
