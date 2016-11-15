package App::Notitia::Model::Admin;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL PIPE_SEP
                                SLOT_TYPE_ENUM SPC TRUE TYPE_CLASS_ENUM );
use App::Notitia::Form      qw( blank_form f_tag p_action p_button p_cell
                                p_container p_item p_js p_link p_list p_radio
                                p_select p_span p_row p_table p_text
                                p_textarea p_textfield );
use App::Notitia::Util      qw( event_handler event_streams js_submit_config
                                loc locm make_tip management_link page_link_set
                                register_action_paths to_msg
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( classdir is_arrayref is_member throw );
use Class::Usul::Types      qw( ArrayRef NonEmptySimpleStr );
use Data::Page;
use Try::Tiny;
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);

# Attribute constructors
my $_build_actions = sub {
   my $self = shift;
   my $class_dir = classdir $self->config->appclass;
   my $libs = $self->config->appldir->catdir( 'lib' )->catdir( $class_dir );

   my $actions = $libs->deep->filter( sub { m{ \. pm \z }mx } )->visit( sub {
      my ($file, $actions) = @_;

      for my $action (map  { s{ [\-] }{_}gmx; $_ }
                      grep { $_ }
                      map  { m{ action: ([^ \$\']+) }mx; $1 }
                      grep { m{ action: }mx } $file->getlines) {
         $actions->{ $action } = TRUE;
      }

      return TRUE;
   } );

   return [ sort keys %{ $actions } ];
};

# Public attributes
has '+moniker' => default => 'admin';

has 'actions' => is => 'lazy', isa => ArrayRef[NonEmptySimpleStr],
   builder => $_build_actions;

register_action_paths
   'admin/event_control'  => 'event-control',
   'admin/event_controls' => 'event-controls',
   'admin/logs'           => 'log',
   'admin/slot_certs'     => 'slot-certs',
   'admin/slot_roles'     => 'slot-roles',
   'admin/type'           => 'type',
   'admin/types'          => 'types';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{page}->{location} //= 'admin';
   $stash->{navigation} = $self->admin_navigation_links( $req, $stash->{page} );

   return $stash;
};

# Private functions
my $_bind_event_controls_role = sub {
   my ($roles, $control) = @_; my $role = $control->role // NUL;

   return [ [ 'Individual', undef ],
            map { [ $_, $_, { selected => $_ eq $role ? TRUE : FALSE } ] }
            @{ $roles } ];
};

my $_create_action = sub {
   return { action => 'create', container_class => 'add-link',
            request => $_[ 0 ] };
};

my $_event_control_status = sub {
   my $control = shift; my $status = $control->status;

   return
      [ [ 'Disabled', 0, { selected => $status ? FALSE : TRUE } ],
        [ 'Enabled',  1, { selected => $status ? TRUE : FALSE } ], ];
};

my $_event_controls_headers = sub {
   my $req = shift; my $max = 4; my $header = 'event_control_heading';

   return [ map { { value => loc $req, "${header}_${_}" } } 0 .. $max ];

};

my $_list_slot_certs = sub {
   my ($schema, $slot_type) = @_; my $rs = $schema->resultset( 'SlotCriteria' );

   return  [ map { $_->certification_type }
             $rs->search( { 'slot_type' => $slot_type },
                          { prefetch    => 'certification_type' } )->all ];
};

my $_list_streams = sub {
   my $control = shift; my $sink = $control->sink;

   return
      [ [ NUL, undef ],
        map  { [ ucfirst $_, $_, { selected => $_ eq $sink ? TRUE : FALSE } ] }
        grep { defined event_handler( $_, '_default_' )->[ 0 ] }
        event_streams ];
};

my $_log_headers = sub {
   my ($req, $logname) = @_; my $max = 2; my $header = 'log_header';

   $logname eq 'activity' and $max = 4 and $header = "${logname}_${header}";

   return [ map { { value => loc $req, "${header}_${_}" } } 0 .. $max ];
};

my $_maybe_find_type = sub {
   return $_[ 2 ] ? $_[ 0 ]->find_type_by( $_[ 2 ], $_[ 1 ] )
                  : Class::Null->new;
};

my $_onchange_submit_event_controls = sub {
   my ($page, $id, $form_name) = @_;

   p_js $page, js_submit_config $id, 'change', 'submitForm',
      [ 'update_event_controls', $form_name ];

   return;
};

my $_ops_link_opts = sub {
   return { class => 'operation-links' };
};

my $_ops_link_right_opts = sub {
   return { class => 'operation-links align-right right-last' };
};

my $_slot_roles_headers = sub {
   return [ map { { value => loc $_[ 0 ], "slot_roles_heading_${_}" } } 0 .. 1];
};

my $_slot_roles_links = sub {
   my ($req, $moniker, $slot_role) = @_;

   my $actionp = $moniker.'/slot_certs'; my $opts = { args => [ $slot_role ] };

   my @links = { value => management_link( $req, $actionp, $slot_role, $opts )};

   return [ { value => loc( $req, $slot_role ) }, @links ];
};

my $_subtract = sub {
   return [ grep { is_arrayref $_ or not is_member $_, $_[ 1 ] } @{ $_[ 0 ] } ];
};

my $_to_action_label = sub {
   my $action = ucfirst shift; $action =~ s{ _ }{ }gmx; return $action;
};

my $_type_create_links = sub {
   my ($req, $moniker, $type_class) = @_;

   my $actionp = "${moniker}/type"; my $links = [];

   if ($type_class) {
      my $k = "${type_class}_type";
      my $href = uri_for_action $req, $actionp, [ $type_class ];

      p_link $links, $k, $href, $_create_action->( $req );
   }
   else {
      for my $type_class (@{ TYPE_CLASS_ENUM() }) {
         my $k = "${type_class}_type";
         my $href = uri_for_action $req, $actionp, [ $type_class ];

         p_link $links, $k, $href, $_create_action->( $req );
      }
   }

   return $links;
};

my $_types_headers = sub {
   return [ map { { value => loc $_[ 0 ], "types_heading_${_}" } } 0 .. 2 ];
};

my $_types_links = sub {
   my ($req, $type) = @_; my $name = $type->name;

   my $opts = { args => [ $type->type_class, $name ] };

   return [ { value => ucfirst locm $req, $type->type_class },
            { value => loc( $req, $type->name ) },
            { value => management_link( $req, 'admin/type', $name, $opts ) } ];
};

# Private methods
my $_event_controls_links = sub {
   my ($self, $req) = @_; my $links = [];

   my $href = uri_for_action $req, $self->moniker.'/event_control';

   p_link $links, 'event_control', $href, {
      action => 'create', container_class => 'add-link', request => $req };

   return $links;
};

my $_event_controls_row = sub {
   my ($self, $req, $page, $roles, $control) = @_; my $row = [];

   my $sink = $control->sink; p_item $row, ucfirst $sink;

   my $action = $control->action;
   my $actionp = $self->moniker.'/event_control';
   my $href = uri_for_action $req, $actionp, [ $sink, $action ];
   my $label = ucfirst $action; $label =~ s{ _ }{ }gmx;
   my $tip = $control->notes || locm $req, 'event_action_tip';
   my $cell = p_cell $row, {};

   p_link $cell, 'event_action', $href, {
      request => $req, tip => $tip, value => $label };

   $actionp = $self->moniker.'/event_controls';
   $href = uri_for_action $req, $actionp, [ $sink, $action ];

   my $form = blank_form 'event-control-status', $href;
   my $status = $control->status ? 'Enabled' : 'Disabled';
   my $value  = $control->status ? 'disable_event' : 'enable_event';
   my $colour = $control->status ? '#99ff33' : '#c00';

   p_item $row, $form, { class => 'narrow' };
   p_button $form, $status, $value, {
      class => 'table-link', style => "color: ${colour};",
      tip => make_tip $req, 'toggle_status_tip', };

   my $form_name = "${sink}-${action}-role";
   my $id = "${sink}_${action}_role";

   $form = blank_form $form_name, $href;

   p_item $row, ($sink eq 'email' or $sink eq 'sms')
      ? $form : NUL, { class => 'embeded narrow' };
   p_select $form, 'role', $_bind_event_controls_role->( $roles, $control ), {
      class => 'narrow-field submit', id => $id, label => NUL };

   $_onchange_submit_event_controls->( $page, $id, $form_name );

   my $title = make_tip $req, 'no_event_handler_tip';

   $cell = p_cell $row, { class => 'centre narrow' }; $self->plugins;

   event_handler( $sink, $action )->[ 0 ] or p_span $cell, '&dagger;', {
      class => 'table-cell-help tips', title => $title };

   return $row;
};

my $_filter_controls = sub {
   my ($self, $req, $logname, $params) = @_;

   my $f_col = $params->{filter_column} // 'none';
   my $href = uri_for_action $req, $self->moniker.'/logs', [ $logname ];
   my $form = blank_form 'filter-controls', $href, { class => 'link-group' };
   my $opts = { class => 'single-character filter-column',
                label_field_class => 'control-label' };
   my @columns = $logname eq 'activity'
               ? qw( action client date detail user )
               : qw( date detail level );

   p_select $form, 'filter_column',
      [ map { [ $_, $_, { selected => $_ eq $f_col ? TRUE : FALSE } ] }
        'none', @columns ], $opts;

   p_textfield $form, 'filter_pattern', $params->{filter_pattern}, {
      class => 'single-character filter-pattern',
      label_field_class => 'control-label' };

   p_button $form, 'filter_log', 'filter_log', {
      class => 'button', tip => make_tip $req, 'filter_log_tip' };

   return $form;
};

my $_list_actions = sub {
   my ($self, $control) = @_; my $action = $control->action;

   return [ [ NUL, undef ],
        map { [ $_to_action_label->( $_ ), $_, {
           selected => $_ eq $action ? TRUE : FALSE } ] }
           @{ $self->actions } ];
};

my $_list_all_certs = sub {
   my $self = shift; my $type_rs = $self->schema->resultset( 'Type' );

   return [ $type_rs->search_for_certification_types->all ];
};

my $_list_roles = sub {
   my ($self, $control) = @_; my $role = $control->role // NUL;

   my $type_rs = $self->schema->resultset( 'Type' );

   return [ [ NUL, undef ],
            map { [ $_, $_->id, { selected => $_ eq $role ? TRUE : FALSE } ] }
            $type_rs->search_for_types( 'role' )->all ];
};

my $_log_user_label = sub {
   my ($self, $data, $field) = @_; (my $scode = $field) =~ s{ \A .+ : }{}mx;

   exists $data->{cache}->{ $scode } and return $data->{cache}->{ $scode };

   my $label;

   try { $label = $data->{person_rs}->find_by_shortcode( $scode )->label }
   catch { $self->log->debug( $_ ) };

   return $label ? $data->{cache}->{ $scode } = $label : NUL;
};

my $_log_columns = sub {
   my ($self, $data, $logname, $line) = @_; my @fields = split SPC, $line, 5;

   my $date = join SPC, @fields[ 0 .. 2 ];

   $data->{filter_column} eq 'date' and $date !~ $data->{filter_pattern}
      and return ();

   my @cols = [ $date, 'log-date' ]; my $detail;

   if ($logname eq 'activity') {
      my @subfields = split SPC, $fields[ 4 ], 4;
      my $label = $self->$_log_user_label( $data, $subfields[ 0 ] );

      $data->{filter_column} eq 'user' and $label !~ $data->{filter_pattern}
         and return ();

      push @cols, [ $label, 'log-user' ];

      (my $client = $subfields[ 1 ]) =~ s{ \A .+ : }{}mx;

      $data->{filter_column} eq 'client' and $client !~ $data->{filter_pattern}
         and return ();

      push @cols, [ $client, 'log-client' ];

      (my $action = $subfields[ 2 ]) =~ s{ \A .+ : }{}mx;

      $data->{filter_column} eq 'action' and $action !~ $data->{filter_pattern}
         and return ();

      push @cols, [ $action, 'log-action' ];

      $detail = $subfields[ 3 ];
   }
   else {
      my $value = $fields[ 3 ]; $value =~ s{ [\[\]] }{}gmx;
      my $level = lc $value;

      $data->{filter_column} eq 'level' and $level !~ $data->{filter_pattern}
         and return ();

      push @cols, [ $value, "log-${level}-level" ];
      $detail = $fields[ 4 ];
   }

   $data->{filter_column} eq 'detail' and $detail !~ $data->{filter_pattern}
         and return ();

   push @cols, [ $detail, 'log-detail' ];

   return @cols;
};

my $_log_rows = sub {
   my ($self, $file, $first, $last, $data, $logname) = @_;

   my $lno = 0; my @rows;

   while (defined (my $line = $file->getline)) {
      $lno < $first and ++$lno and next; $lno > $last and ++$lno and next;
      $line =~ m{ \A [a-zA-z]{3} [ ] \d+ [ ] \d+ : }mx or next;

      my @cols = $self->$_log_columns( $data, $logname, $line ); @cols or next;

      push @rows, [ map { { class => $_->[ 1 ], value => $_->[ 0 ] } } @cols ];
      $lno++;
   }

   return ($lno, @rows);
};

my $_maybe_find_control = sub {
   my ($self, $sink, $action) = @_; my $object;

   my $rs = $self->schema->resultset( 'EventControl' );

   $sink and $action and ($object = $rs->find( $sink, $action )
      or throw 'Stream [_1] action [_2] unknown', [ $sink, $action ]);

   return $object ? $object : Class::Null->new;
};

my $_toggle_event_status = sub {
   my ($self, $req, $status, $verb) = @_;

   my $sink = $req->uri_params->( 0 );
   my $action = $req->uri_params->( 1 );
   my $rs = $self->schema->resultset( 'EventControl' );
   my $control = $rs->find( $sink, $action );

   $control->status( $status ); $control->update;

   return [ to_msg "Stream [_1] action [_2] ${verb} by [_3]",
            $sink, $action, $req->session->user_label ];
};

# Public methods
sub add_certification_action : Role(administrator) {
   my ($self, $req) = @_;

   my $slot_type = $req->uri_params->( 0 );
   my $type_rs   = $self->schema->resultset( 'Type' );
   my $certs     = $req->body_params->( 'certs', { multiple => TRUE } );

   for my $cert_name (@{ $certs }) {
      my $cert_type = $type_rs->find_certification_by( $cert_name );

      $cert_type->add_cert_type_to( $slot_type );
   }

   my $message  = [ to_msg '[_1] slot role cert(s). added by [_2]',
                    $slot_type, $req->session->user_label ];
   my $location = uri_for_action $req, $self->moniker.'/slot_roles';

   return { redirect => { location => $location, message => $message } };
}

sub add_type_action : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $name     =  $req->body_params->( 'name' );
   my $person   =  $self->schema->resultset( 'Type' )->create( {
      name      => $name, type_class => $type_class } );
   my $message  =  [ to_msg 'Type [_1] class [_2] created by [_3]',
                     $name, $type_class, $req->session->user_label ];
   my $location =  uri_for_action $req, $self->moniker.'/types';

   return { redirect => { location => $location, message => $message } };
}

sub create_event_control_action : Role(administrator) {
   my ($self, $req) = @_;

   my $rs = $self->schema->resultset( 'EventControl' );
   my $params = $req->body_params->( { optional => TRUE } );

   delete $params->{_method}; $params->{role_id} or delete $params->{role_id};

   my $control = $rs->create( $params );
   my $message = [ to_msg 'Stream [_1] action [_2] control created by [_3]',
                   $control->sink, $control->action, $req->session->user_label];
   my $location = uri_for_action $req, $self->moniker.'/event_controls';

   return { redirect => { location => $location, message => $message } };
}

sub delete_event_control_action : Role(administrator) {
   my ($self, $req) = @_;

   my $sink = $req->uri_params->( 0 );
   my $ev_action = $req->uri_params->( 1 );
   my $rs = $self->schema->resultset( 'EventControl' );
   my $control = $rs->find( $sink, $ev_action ); $control->delete;
   my $message = [ to_msg 'Stream [_1] action [_2] control deleted by [_3]',
                   $sink, $ev_action, $req->session->user_label];
   my $location = uri_for_action $req, $self->moniker.'/event_controls';

   return { redirect => { location => $location, message => $message } };
}

sub disable_event_action : Role(administrator) {
   my ($self, $req) = @_;

   my $message = $self->$_toggle_event_status( $req, FALSE, 'disabled' );

   return { redirect => { message => $message } }; # location referer
}

sub enable_event_action : Role(administrator) {
   my ($self, $req) = @_;

   my $message = $self->$_toggle_event_status( $req, TRUE, 'enabled' );

   return { redirect => { message => $message } }; # location referer
}

sub event_control : Role(administrator) {
   my ($self, $req) = @_; $self->plugins;

   my $sink = $req->uri_params->( 0, { optional => TRUE } );
   my $ev_action = $req->uri_params->( 1, { optional => TRUE } );
   my $action = $sink && $ev_action ? 'update' : 'create';
   my $args = [ $sink, $ev_action ];
   my $href = uri_for_action $req, $self->moniker.'/event_control', $args;
   my $form = blank_form 'event-control', $href;
   my $page = {
      forms => [ $form ], selected => 'event_controls',
      title => locm $req, 'event_control_title',
   };
   my $control = $self->$_maybe_find_control( $sink, $ev_action );
   my $disabled = $action eq 'update' ? TRUE : FALSE;

   p_select $form, 'sink', $_list_streams->( $control ), {
      class => 'standard-field required', disabled => $disabled,
      label => 'event_stream' };

   p_select $form, 'action', $self->$_list_actions( $control ), {
      class => 'standard-field required', disabled => $disabled,
      label => 'event_action' };

   p_radio $form, 'status', $_event_control_status->( $control ), {
      label => 'action_status' };

   p_select $form, 'role_id', $self->$_list_roles( $control ), {
      label => 'action_role' };

   p_textarea $form, 'notes', $control->notes, {
      class => 'standard-field autosize' };

   $args = [ 'event_control', $sink ? "${sink} / ${ev_action}" : NUL ];
   p_action $form, $action, $args, { request => $req };

   $sink and $ev_action
      and not event_handler( $sink, $ev_action )->[ 0 ]
      and p_action $form, 'delete', $args, { request => $req};

   return $self->get_stash( $req, $page );
}

sub event_controls : Role(administrator) {
   my ($self, $req) = @_;

   my $form = blank_form;
   my $page = {
      forms => [ $form ], selected => 'event_controls',
      title => locm $req, 'event_controls_title',
   };
   my $type_rs = $self->schema->resultset( 'Type' );
   my $roles = [ $type_rs->search_for_types( 'role' )->all ];
   my $ec_rs = $self->schema->resultset( 'EventControl' );
   my $links = $self->$_event_controls_links( $req );

   p_list $form, PIPE_SEP, $links, $_ops_link_right_opts->();

   my $table = p_table $form, { headers => $_event_controls_headers->( $req ) };

   p_row $table, [ map { $self->$_event_controls_row( $req, $page, $roles, $_ )}
                   $ec_rs->search( {} )->all ];

   my $href = uri_for_action $req, $self->moniker.'/event_controls';

   $form = $page->{forms}->[ 1 ] = blank_form 'event-controls', $href, {
      class => 'wide-form' };

   p_button $form, 'init_event_controls', 'init_event_controls', {
      class => 'save-button', container_class => 'right-last',
      tip => make_tip $req, 'init_event_controls_tip' };

   return $self->get_stash( $req, $page );
}

sub filter_log_action : Role(administrator) {
   my ($self, $req) = @_;

   my $args = [ $req->uri_params->( 0 ) ];
   my $column = $req->body_params->( 'filter_column' );
   my $pattern = $req->body_params->( 'filter_pattern' );
   my $params = { filter_column => $column, filter_pattern => $pattern };
   my $location = uri_for_action $req, $self->moniker.'/logs', $args, $params;

   return { redirect => { location => $location } };
}

sub init_event_controls_action : Role(administrator) {
   my ($self, $req) = @_;

   $self->update_event_control_from_cache;

   my $message = [ to_msg 'Updated event control from event handler cache' ];

   return { redirect => { message => $message } }; # location referer
}

sub logs : Role(administrator) {
   my ($self, $req) = @_;

   my $logname = $req->uri_params->( 0 );
   my $form = blank_form;
   my $page = {
      selected => $logname, forms => [ $form ],
      title => locm $req, 'logs_title', ucfirst locm $req, $logname,
   };
   my $dir = $self->config->logsdir;
   my $file = $dir->catfile( "${logname}.log" )->backwards->chomp;

   $file->exists or return $self->get_stash( $req, $page );

   my $pageno = $req->query_params->( 'page', { optional => TRUE } ) || 1;
   my $rows_pp = $req->session->rows_per_page;
   my $first = $rows_pp * ($pageno - 1);
   my $last = $rows_pp * $pageno - 1;
   my $queryp = $req->query_params;
   my $column = $queryp->( 'filter_column', { optional => TRUE } ) // 'none';
   my $pattern = $queryp->( 'filter_pattern', { optional => TRUE } ) // NUL;
   my $data = { cache => {}, filter_column => $column,
                filter_pattern => qr{ $pattern }imx,
                person_rs => $self->schema->resultset( 'Person' ) };
   my ($lno, @rows) = $self->$_log_rows( $file, $first, $last, $data, $logname);
   my $actp = $self->moniker.'/logs';
   my $params = { filter_column => $column, filter_pattern => $pattern, };
   my $dp = Data::Page->new( $lno, $rows_pp, $pageno );
   my $opts = { class => 'log-links right-last' };
   my $plinks = page_link_set $req, $actp, [ $logname ], $params, $dp, $opts;
   my $links = [ $self->$_filter_controls( $req, $logname, $params ), $plinks ];

   p_list $form, NUL, $links, $_ops_link_opts->();

   my $table = p_table $form, {
      class => 'smaller-table', headers => $_log_headers->( $req, $logname ) };

   p_row $table, [ @rows ];
   p_list $form, NUL, $links, $_ops_link_opts->();

   return $self->get_stash( $req, $page );
}

sub remove_certification_action : Role(administrator) {
   my ($self, $req) = @_;

   my $slot_type = $req->uri_params->( 0 );
   my $type_rs   = $self->schema->resultset( 'Type' );
   my $certs     = $req->body_params->( 'slot_certs', { multiple => TRUE } );

   for my $cert_name (@{ $certs }) {
      my $cert_type = $type_rs->find_certification_by( $cert_name );

      $cert_type->delete_cert_type_from( $slot_type );
   }

   my $message  = [ to_msg '[_1] slot role cert(s). deleted by [_2]',
                    $slot_type, $req->session->user_label ];
   my $location = uri_for_action $req, $self->moniker.'/slot_roles';

   return { redirect => { location => $location, message => $message } };
}

sub remove_type_action : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $name     = $req->uri_params->( 1 );
   my $type_rs  = $self->schema->resultset( 'Type' );
   my $type     = $type_rs->find_type_by( $name, $type_class ); $type->delete;
   my $message  = [ to_msg 'Type [_1] class [_2] deleted by [_3]',
                    $name, $type_class, $req->session->user_label ];
   my $location =  uri_for_action $req, $self->moniker.'/types';

   return { redirect => { location => $location, message => $message } };
}

sub slot_certs : Role(administrator) {
   my ($self, $req) = @_;

   my $slot_type  =  $req->uri_params->( 0 );
   my $actionp    =  $self->moniker.'/slot_certs';
   my $href       =  uri_for_action $req, $actionp, [ $slot_type ];
   my $form       =  blank_form 'role-certs-admin', $href;
   my $page       =  {
      forms       => [ $form ],
      selected    => 'slot_roles_list',
      title       => loc( $req, 'slot_certs_management_heading' ), };
   my $slot_certs =  $_list_slot_certs->( $self->schema, $slot_type );
   my $available  =  $_subtract->( $self->$_list_all_certs, $slot_certs );

   p_textfield $form, 'slotname', loc( $req, $slot_type ), { disabled => TRUE };

   p_select $form, 'slot_certs', $slot_certs, { multiple => TRUE, size => 5 };

   p_button $form, 'remove_certification', 'remove_certification', {
      class => 'delete-button', container_class => 'right-last',
      tip   => make_tip( $req, 'remove_certification_tip',
                         [ 'certification', $slot_type ] ) };

   p_container $form, f_tag( 'hr' ), { class => 'form-separator' };

   p_select $form, 'certs', $available, { multiple => TRUE, size => 10 };

   p_button $form, 'add_certification', 'add_certification', {
      class => 'save-button', container_class => 'right-last',
      tip   => make_tip( $req, 'add_certification_tip',
                         [ 'certification', $slot_type ] ) };

   return $self->get_stash( $req, $page );
};

sub slot_roles : Role(administrator) {
   my ($self, $req) = @_;

   my $form    =  blank_form;
   my $page    =  {
      forms    => [ $form ],
      selected => 'slot_roles_list',
      title    => loc $req, 'slot_roles_list_link' };
   my $table   =  p_table $form, { headers => $_slot_roles_headers->( $req ) };

   p_row $table, [ map { $_slot_roles_links->( $req, $self->moniker, $_ ) }
                      @{ SLOT_TYPE_ENUM() } ];

   return $self->get_stash( $req, $page );
}

sub type : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $actionp    =  $self->moniker.'/type';
   my $name       =  $req->uri_params->( 1, { optional => TRUE } );
   my $type_rs    =  $self->schema->resultset( 'Type' );
   my $type       =  $_maybe_find_type->( $type_rs, $type_class, $name );
   my $args       =  [ $type_class ]; $name and push @{ $args }, $name;
   my $href       =  uri_for_action $req, $actionp, $args;
   my $form       =  blank_form 'type-admin', $href;
   my $disabled   =  $name ? TRUE : FALSE;
   my $class_name =  ucfirst locm $req, $type_class;
   my $page       =  {
      first_field => 'name',
      forms       => [ $form ],
      selected    => 'types_list',
      title       => locm $req, 'type_management_heading', $class_name };

   p_textfield $form, 'name', loc( $req, $type->name ), {
      disabled => $disabled, label => 'type_name' };

   if ($name) {
      p_button $form, 'remove_type', 'remove_type', {
         class => 'delete-button', container_class => 'right-last',
         tip   => make_tip $req, 'remove_type_tip', $args };
   }
   else {
      p_button $form, 'add_type', 'add_type', {
         class => 'save-button', container_class => 'right-last',
         tip   => make_tip $req, 'add_type_tip', $args };
   }

   return $self->get_stash( $req, $page );
}

sub types : Role(administrator) {
   my ($self, $req) = @_;

   my $moniker    =  $self->moniker;
   my $type_class =  $req->query_params->( 'type_class', { optional => TRUE } );
   my $form       =  blank_form;
   my $page       =  {
      forms       => [ $form ],
      selected    => $type_class ? "${type_class}_list" : 'types_list',
      title       => loc( $req, $type_class ? "${type_class}_list_link"
                                            : 'types_management_heading' ), };
   my $type_rs    =  $self->schema->resultset( 'Type' );
   my $types      =  $type_class ? $type_rs->search_for_types( $type_class )
                                 : $type_rs->search_for_all_types;
   my $links      =  $_type_create_links->( $req, $moniker, $type_class );

   p_list $form, PIPE_SEP, $links, $_ops_link_right_opts->();

   my $table = p_table $form, { headers => $_types_headers->( $req ) };

   p_row $table, [ map { $_types_links->( $req, $_ ) } $types->all ];

   p_list $form, PIPE_SEP, $links, $_ops_link_right_opts->();

   return $self->get_stash( $req, $page );
}

sub update_event_control_action : Role(administrator) {
   my ($self, $req) = @_;

   my $sink = $req->uri_params->( 0 );
   my $ev_action = $req->uri_params->( 1 );
   my $rs = $self->schema->resultset( 'EventControl' );
   my $control = $rs->find( $sink, $ev_action );
   my $params = $req->body_params;
   my $role_id = $params->( 'role_id', { optional => TRUE } );

   $role_id or $role_id = undef; $control->role_id( $role_id );
   $control->notes( $params->( 'notes', { optional => TRUE } // NUL ) );
   $control->status( $params->( 'status' ) );
   $control->update;

   my $message = [ to_msg 'Stream [_1] action [_2] control updated by [_3]',
                   $sink, $ev_action, $req->session->user_label];
   my $location = uri_for_action $req, $self->moniker.'/event_controls';

   return { redirect => { location => $location, message => $message } };
}

sub update_event_controls_action : Role(administrator) {
   my ($self, $req) = @_;

   my $sink = $req->uri_params->( 0 );
   my $action = $req->uri_params->( 1 );
   my $rs = $self->schema->resultset( 'EventControl' );
   my $control = $rs->find( $sink, $action );
   my $role_name = $req->body_params->( 'role', { optional => TRUE } );
   my $type_rs = $self->schema->resultset( 'Type' );
   my $role = $role_name ? $type_rs->find_role_by( $role_name ) : undef;

   $control->role_id( $role ? $role->id : undef ); $control->update;

   my $message = [ to_msg 'Stream [_1] action [_2] updated by [_3]',
                   $sink, $action, $req->session->user_label ];

   return { redirect => { message => $message } }; # location referer
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Admin - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Admin;
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
