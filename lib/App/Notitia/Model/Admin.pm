package App::Notitia::Model::Admin;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( FALSE NUL TRUE TYPE_CLASS_ENUM );
use App::Notitia::Util      qw( bind_fields button create_link loc
                                management_link register_action_paths
                                uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(App::Notitia::Role::Navigation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'admin';

register_action_paths
   'admin/type' => 'type', 'admin/types' => 'types';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav }->{list    }   = $self->admin_navigation_links( $req );
   $stash->{page}->{location} //= 'admin';

   return $stash;
};

# Private class attributes
my $_types_links_cache = {};

# Private functions
my $_add_type_button = sub {
   return button $_[ 0 ], { class => 'right-last' }, 'add', 'type', $_[ 1 ];
};

my $_add_type_create_links = sub {
   my ($req, $moniker, $type_class) = @_;

   my $actionp = "${moniker}/type"; my $links = [];

   if ($type_class) {
      my $k = "${type_class}_type"; my $opts = { args => [ $type_class ] };

      push @{ $links }, create_link( $req, $actionp, $k, $opts );
   }
   else {
      for my $type_class (@{ TYPE_CLASS_ENUM() }) {
         my $k = "${type_class}_type"; my $opts = { args => [ $type_class ] };

         push @{ $links }, create_link( $req, $actionp, $k, $opts );
      }
   }

   return { list => $links, separator => '|', type => 'list', };
};

my $_bind_type_fields = sub {
   my ($schema, $type, $opts) = @_; $opts //= {};

   my $disabled  =  $opts->{disabled} // FALSE;
   my $map       =  {
      name       => { disabled => $disabled, label => 'type_name' }, };

   return bind_fields $schema, $type, $map, 'Type';
};

my $_remove_type_button = sub {
   return button $_[ 0 ], { class => 'right-last' }, 'remove', 'type', $_[ 1 ];
};

my $_maybe_find_type = sub {
   return $_[ 2 ] ? $_[ 0 ]->find_type_by( $_[ 2 ], $_[ 1 ] )
                  : Class::Null->new;
};

my $_types_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "types_heading_${_}" ) } } 0 .. 2 ];
};

my $_types_links = sub {
   my ($req, $type) = @_; my $name = $type->name;

   my $links = $_types_links_cache->{ $name }; $links and return @{ $links };

   $links = []; my $opts = { args => [ $type->type_class, $type->name ] };

   for my $actionp ( qw( admin/type ) ) {
      push @{ $links },
            { value => management_link( $req, $actionp, $name, $opts ) };
   }

   $_types_links_cache->{ $name } = $links;

   return @{ $links };
};

# Public methods
sub add_type_action : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $name     =  $req->body_params->( 'name' );
   my $person   =  $self->schema->resultset( 'Type' )->create( {
      name      => $name, type_class => $type_class } );
   my $message  =  [ 'Type [_1] class [_2] created', $name, $type_class ];
   my $location =  uri_for_action $req, $self->moniker.'/types';

   return { redirect => { location => $location, message => $message } };
}

sub remove_type_action : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $name     = $req->uri_params->( 1 );
   my $type_rs  = $self->schema->resultset( 'Type' );
   my $type     = $type_rs->find_type_by( $name, $type_class ); $type->delete;
   my $message  = [ 'Type [_1] class [_2] deleted', $name, $type_class ];
   my $location =  uri_for_action $req, $self->moniker.'/types';

   return { redirect => { location => $location, message => $message } };
}

sub type : Role(administrator) {
   my ($self, $req) = @_; my $type_class = $req->uri_params->( 0 );

   is_member $type_class, TYPE_CLASS_ENUM
      or throw 'Type class [_1] unknown', [ $type_class ];

   my $name       =  $req->uri_params->( 1, { optional => TRUE } );
   my $type_rs    =  $self->schema->resultset( 'Type' );
   my $type       =  $_maybe_find_type->( $type_rs, $type_class, $name );
   my $opts       =  { disabled => $name ? TRUE : FALSE };
   my $page       =  {
      fields      => $_bind_type_fields->( $self->schema, $type, $opts ),
      first_field => 'name',
      template    => [ 'contents', 'type' ],
      title       => loc( $req, 'type_management_heading',
                          { params => [ ucfirst $type_class ],
                            no_quote_bind_values => TRUE, } ), };
   my $fields     =  $page->{fields};
   my $actionp    =  $self->moniker.'/type';
   my $args       =  [ $type_class ]; $name and push @{ $args }, $name;

   $fields->{href} = uri_for_action $req, $actionp, $args;

   if ($name) { $fields->{remove} = $_remove_type_button->( $req, $args ) }
   else { $fields->{add} = $_add_type_button->( $req, $args ) }

   return $self->get_stash( $req, $page );
}

sub types : Role(administrator) {
   my ($self, $req) = @_;

   my $moniker    =  $self->moniker;
   my $type_class =  $req->query_params->( 'type_class', { optional => TRUE } );
   my $page       =  {
      fields      => {
         add      => $_add_type_create_links->( $req, $moniker, $type_class ),
         headers  => $_types_headers->( $req ),
         rows     => [], },
      template    => [ 'contents', 'table' ],
      title       => loc( $req, $type_class ? "${type_class}_list_link"
                                            : 'types_management_heading' ), };
   my $type_rs    =  $self->schema->resultset( 'Type' );
   my $types      =  $type_class ? $type_rs->list_types( $type_class )
                                 : $type_rs->list_all_types;
   my $rows       =  $page->{fields}->{rows};

   for my $type ($types->all) {
      push @{ $rows }, [ { value => ucfirst $type->type_class },
                         { value => loc( $req, $type->name ) },
                         $_types_links->( $req, $type ) ];
   }

   return $self->get_stash( $req, $page );
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
