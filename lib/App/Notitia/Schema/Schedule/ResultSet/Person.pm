package App::Notitia::Schema::Schedule::ResultSet::Person;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SPC TRUE );
use Class::Usul::Functions  qw( throw );

# Private package variables
my $_max_badge_id = [ 0, 0 ];

# Private functions
my $_person_tuple = sub {
   my ($person, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{selected} //= NUL;
   $opts->{selected}   = $opts->{selected} eq $person ? TRUE : FALSE;

   return [ $person->label, $person, $opts ];
};

# Private methods
my $_find_role_type = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_role_by( $name );
};

my $_get_max_badge_id = sub {
   my $self = shift; my $dir = $self->result_source->schema->config->ctrldir;

   my $path = $dir->catfile( 'max_badge_id' ); $path->exists or return;

   return $path->lock->chomp->getline;
};

my $_load_cache = sub {
   my ($self, $cache) = @_; my $opts = { columns => [ 'badge_id' ] };

   for my $person ($self->search_for_people( $opts )->all) {
      defined $person->badge_id
          and $cache->{badge_id}->{ $person->badge_id } = TRUE;
      $cache->{shortcode}->{ $person->shortcode } = TRUE;
   }

   return;
};

my $_set_max_badge_id = sub {
   my ($self, $v) = @_; my $conf = $self->result_source->schema->config;

   $v >= $conf->badge_excludes->[ 0 ] and $v <= $conf->badge_excludes->[ 1 ]
      and $v = $conf->badge_excludes->[ 1 ] + 1;

   $conf->ctrldir->catfile( 'max_badge_id' )->lock->println( $v );

   return $v;
};

# Public methods
sub find_by_key {
   my ($self, $key) = @_; my $person;

   defined( $person = $self->search( { name => $key } )->single )
       and  return $person;
   defined( $person = $self->search( { shortcode => $key } )->single )
       and  return $person;
   defined( $person = $self->search( { email_address => $key } )->single )
       and  return $person;

   throw 'Person [_1] unknown', [ $key ], level => 2;
}

sub find_person { # Deprecated
   return $_[ 0 ]->find_by_key( $_[ 1 ] );
}

sub find_by_shortcode {
   my ($self, $shortcode, $opts) = @_; $opts //= {};

   my $person = $self->search( { shortcode => $shortcode }, $opts )->single;

   defined $person or throw 'Person [_1] unknown', [ $shortcode ], level => 2;

   return $person;
}

sub is_badge_free {
   my ($self, $badge_id, $cache) = @_; $cache //= {};

   exists $cache->{badge_id} or $self->$_load_cache( $cache );

   return exists $cache->{badge_id}->{ $badge_id } ? FALSE : TRUE;
}

sub is_person {
   my ($self, $shortcode, $cache) = @_; $cache //= {};

   exists $cache->{shortcode} or $self->$_load_cache( $cache );

   return exists $cache->{shortcode}->{ $shortcode } ? TRUE : FALSE;
}

sub list_all_people {
   my ($self, $opts) = @_;

   my $people = $self->search_for_people( $opts );

   return [ map { $_person_tuple->( $_, $opts->{fields} ) } $people->all ];
}

sub list_participents {
   my ($self, $event, $opts) = @_; $opts = { %{ $opts // {} } };

   my $fields  = delete $opts->{fields} // {};
   my $columns = [ 'first_name', 'id', 'last_name', 'name', 'shortcode' ];

   $opts->{columns} and push @{ $columns }, @{ delete $opts->{columns} };

   my $people  = $self->search
      ( { 'participents.event_id' => $event->id },
        { columns  => $columns,
          join     => [ 'participents' ], %{ $opts } } );

   return [ map { $_person_tuple->( $_, $fields ) } $people->all ];
}

sub list_people {
   my ($self, $role, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{prefetch} //= []; push @{ $opts->{prefetch} }, 'roles';

   # TODO: Inefficient query not processing restriction on data server
   my $people = $self->list_all_people( $opts );
   my $type   = $self->$_find_role_type( $role );

   return [ grep { $_->[ 1 ]->is_member_of( $role, $type ) } @{ $people } ];
}

sub max_badge_id {
   my ($self, $v) = @_;

   defined $v and $v > $_max_badge_id->[ 1 ]
       and return $_max_badge_id->[ 1 ] = $self->$_set_max_badge_id( $v );

   my $conf    = $self->result_source->schema->config;
   my $file    = $conf->badge_mtime; $file->exists or $file->touch;
   my $f_mtime = $file->stat->{mtime};

   $f_mtime <= $_max_badge_id->[ 0 ] and return $_max_badge_id->[ 1 ];

   my $max_f = $self->$_get_max_badge_id;
   my $where = { 'badge_id' => { '!=' => undef } };

   $conf->badge_excludes->[ 0 ] and
      $where = { 'badge_id' => [ -and => { '!=' => undef }, [ -or => {
         '<' => $conf->badge_excludes->[ 0 ] }, {
            '>' => $conf->badge_excludes->[ 1 ] } ] ] };

   my $max_d = $self->search( $where )->get_column( 'badge_id' )->max;
   my $max   = $_max_badge_id->[ 1 ]; $_max_badge_id->[ 0 ] = $f_mtime;

   $max_f and $max_f > $max and $max = $max_f;
   $max_d and $max_d > $max and $max = $max_d;

   return $_max_badge_id->[ 1 ] = $self->$_set_max_badge_id( $max );
}

sub next_badge_id {
   return $_[ 0 ]->max_badge_id( $_[ 0 ]->max_badge_id + 1 );
}

sub search_by_period {
   my ($self, $opts) = @_;

   my $parser = $self->result_source->schema->datetime_parser;
   my $after  = $parser->format_datetime( $opts->{after} );
   my $before = $parser->format_datetime( $opts->{before} );
   my $where  = {
      $self->me( 'joined' ) => { '!=' => undef },
      $self->me( 'joined' ) => { '<'  => $before },
      $self->me( 'resigned' ) => [ { '=' => undef },
                                   { '>' => $after, '<' => $before } ], };
   my $cols   = [ 'joined', 'resigned', 'shortcode' ];
   my $order  = [ $self->me( 'joined' ) ];
   my $fetch  = [ { 'roles' => 'type' } ];

   $opts = { columns => $cols, order_by => $order, prefetch => $fetch };

   return $self->search( $where, $opts );
}

sub search_for_people {
   my ($self, $opts) = @_; $opts = { %{ $opts // {} } };

   delete $opts->{fields}; $opts->{prefetch} //= [];

   my $status  = delete $opts->{status} // NUL;
   my $where   = $status eq 'current'
               ? { $self->me( 'resigned' ) => { '=' => undef },
                   $self->me( 'active'   ) => TRUE, } : {};
   my $columns = [ 'first_name', 'id', 'last_name', 'name', 'shortcode' ];

   $opts->{columns} and push @{ $columns }, @{ delete $opts->{columns} };

   if (my $type = delete $opts->{type}) {
      if ($type eq 'contacts') {
         push @{ $opts->{prefetch} }, 'next_of_kin';
         push @{ $columns }, 'home_phone', 'mobile_phone';
      }
   }

   if (my $role = delete $opts->{role}) {
      push @{ $opts->{prefetch} }, 'roles';
      $where->{ 'roles.type_id' } = $self->$_find_role_type( $role )->id;
   }

   return $self->search
      ( $where, { columns  => $columns, order_by => [ $self->me( 'name' ) ],
               %{ $opts } } );
}

sub me {
   return join '.', $_[ 0 ]->current_source_alias, $_[ 1 ] // NUL;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Person - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Person;
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
