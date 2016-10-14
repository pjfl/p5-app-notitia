package App::Notitia::Form;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Util      qw( locm make_tip );
use App::Notitia::Constants qw( FALSE HASH_CHAR NUL TRUE );
use Class::Usul::Functions  qw( is_arrayref is_hashref throw );
use Scalar::Util            qw( blessed );

our @EXPORT_OK = qw( blank_form f_link f_tag p_action p_button p_cell
                     p_checkbox p_container p_date p_fields p_file p_hidden
                     p_image p_item p_label p_link p_list p_password p_radio
                     p_row p_select p_slider p_span p_table p_tag p_text
                     p_textarea p_textfield p_unordered );

# Private package variables
my @ARG_NAMES = qw( name href opts );

my $field_option_cache = {};

# Private functions
my $_bind_option = sub {
   my ($v, $opts) = @_;

   my $prefix = $opts->{prefix} // NUL; my $numify = $opts->{numify} // FALSE;

   return is_arrayref $v
        ? { label =>  $v->[ 0 ].NUL,
            value => (defined $v->[ 1 ]
                      ? ($numify ? 0 + ($v->[ 1 ] || 0) : $prefix.$v->[ 1 ])
                      : undef),
            %{ $v->[ 2 ] // {} } }
        : { label => "${v}", value => ($numify ? 0 + $v : $prefix.$v) };
};

my $_bind = sub {
   my ($name, $v, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{name} = $name; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $opts->{value} = $v->clone->set_time_zone( 'local' )->dmy( '/' );
   }
   elsif (is_arrayref $v) {
      $opts->{value} = [ map { $_bind_option->( $_, $opts ) } @{ $v } ];
   }
   elsif (defined $v) { $opts->{value} = $opts->{numify} ? 0 + $v : "${v}" }
   else { $opts->{value} = NUL }

   return $opts;
};

my $_f_list = sub {
   my ($sep, $list) = @_; $sep //= NUL; $list //= [];

   return { list => $list, separator => $sep, type => 'list' };
};

my $_field_options = sub {
   my ($schema, $result, $name, $opts) = @_; $opts = { %{ $opts // {} } };

   my $mandy;

   unless (defined ($mandy = $field_option_cache->{ $result }->{ $name })) {
      my $class       = blessed $schema->resultset( $result )->new_result( {} );
      my $constraints = $class->validation_attributes->{fields}->{ $name };

      $mandy = $field_option_cache->{ $result }->{ $name }
             = exists $constraints->{validate}
                   && $constraints->{validate} =~ m{ isMandatory }mx
             ? ' required' : NUL;
   }

   $opts->{class} //= NUL; $opts->{class} .= $mandy;

   return $opts;
};

my $_inline_args = sub {
   my $n = shift; return (map { $ARG_NAMES[ $_ ] => $_[ $_ ] } 0 .. $n - 1);
};

my $_natatime = sub {
   my $n = shift; my @list = @_;

   return sub { return $_[ 0 ] ? unshift @list, @_ : splice @list, 0, $n };
};

my $_parse_args = sub {
   my $n = 0; $n++ while (defined $_[ $n ]);

   return           ( $n == 0 ) ? { opts => {} }
        : is_hashref( $_[ 0 ] ) ? { opts => $_[ 0 ] }
        :           ( $n == 1 ) ? throw 'Insufficient number of args'
        : is_hashref( $_[ 1 ] ) ? { content => $_[ 0 ], opts => $_[ 1 ] }
        :           ( $n == 2 ) ? { $_inline_args->( 2, @_ ) }
        :           ( $n == 3 ) ? { $_inline_args->( 3, @_ ) }
                                : { @_ };
};

my $_push_to = sub {
   my ($f, $opts) = @_;

   my $list = is_arrayref $f ? $f
            : is_arrayref $f->{list} ? $f->{list}
            : is_arrayref $f->{content}->{list} ? $f->{content}->{list}
            : is_hashref  $f ? FALSE : throw 'No field to push to';

   if ($list) { push @{ $list }, $opts } else { $f->{value} = $opts }

   return $opts;
};

my $_push_field = sub {
   my ($f, $type, $opts) = @_; $opts = { %{ $opts } }; $opts->{type} = $type;

   defined $opts->{name} and $opts->{label} //= $opts->{name};

   return $_push_to->( $f, $opts );
};

# Public functions
sub blank_form (;$$$) {
   my $attr = $_parse_args->( @_ ); my $opts = { %{ $attr->{opts} // {} } };

   $attr->{name} and $attr->{href} and return {
      content => { list => [], type => 'list' }, href => $attr->{href},
      form_name => $attr->{name}, type => 'form', %{ $opts } };

   $opts->{type} and ($opts->{type} eq 'list' or $opts->{type} eq 'unordered')
      and $opts->{list} //= [] and $opts->{content} = NUL;
   $opts->{content} //= { list => [], type => 'list' };
   $opts->{type} //= 'container';

   return $opts;
}

sub f_link (@) {
   my ($name, $x, $opts) = @_; $opts = { %{ $opts // {} } };

   my $href   = !defined( $x )  ? HASH_CHAR
              :  blessed( $x ) || !is_hashref( $x ) ? $x
              : ($opts = { %{ $x }, %{ $opts } })   ? HASH_CHAR : undef;
   my $req    = delete $opts->{request};
   my $action = delete $opts->{action} // NUL;
   my $args   = delete $opts->{args};
   my $dvalue = $action ? ucfirst "${action} ${name}" : ucfirst $name;

   $action and $action .= '_';

   my $tkey   = "${name}_${action}tip";
   my $tip    = $req ? locm( $req, $tkey, @{ $args // [] } ) : $tkey;
   my $vkey   = "${name}_${action}link";
   my $value  = $req ? locm( $req, $vkey ) : $dvalue;
   my $hint   = $req ? locm( $req, 'Hint' ) : 'Hint';

   return { hint => $hint, href => $href,
            name => "${action}${name}", tip => $tip,
            type => 'link', value => $value, %{ $opts } };
}

sub f_tag (@) {
   my ($tag, $content, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{orig_type} = delete $opts->{type}; $content //= NUL;

   return { content => $content, tag => $tag, type => 'tag', %{ $opts } };
}

sub p_action ($@) {
   my ($f, $action, $args, $opts) = @_; $opts = { %{ $opts // {} } };

   my $name   = $args->[ 0 ];
   my $prefix = $action eq 'create' ? 'save-'
              : $action eq 'delete' ? 'delete-'
              : $action eq 'update' ? 'save-'
              : NUL;
   my $conk   = $action eq 'create' ? 'right-last'
              : $action eq 'delete' ? 'right'
              : $action eq 'update' ? 'right-last'
              : NUL;
   my $req    = delete $opts->{request};
   my $tip    = $req ? make_tip $req, "${action}_tip", $args : NUL;

   return p_button( $f, $action, "${action}_${name}", {
      class => "${prefix}button", container_class => $conk,
      tip   => $tip, %{ $opts } } );
}

sub p_button ($@) {
   my $f = shift; return $_push_field->( $f, 'button', $_bind->( @_ ) );
}

sub p_cell ($;$) {
   my ($row, $x) = @_;

   if (not $x or is_hashref $x) { push @{ $row }, $x //= {}; return $x }

   return push @{ $row }, @{ $x };
}

sub p_checkbox ($@) {
   my $f = shift; return $_push_field->( $f, 'checkbox', $_bind->( @_ ) );
}

sub p_container ($@) {
   my ($f, $content, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{content} = $content;

   return $_push_field->( $f, 'container', $opts );
}

sub p_date ($@) {
   my $f = shift; return $_push_field->( $f, 'date', $_bind->( @_ ) );
}

sub p_fields ($$$$$) {
   my ($f, $schema, $result, $src, $map) = @_;

   my $iter = $_natatime->( 2, @{ $map } );

   while (my ($k, $opts) = $iter->()) {
      $opts or next; my $type = $opts->{type} // 'textfield';

      if    ($type eq 'checkbox') { $opts = $_bind->( $k, TRUE, $opts ) }
      elsif ($type eq 'image') {}
      elsif ($type eq 'radio' or $type eq 'select') {
         $opts = $_field_options->( $schema, $result, $k, $opts );
         $opts = $_bind->( $k, delete $opts->{value}, $opts );
      }
      else {
         my $v = defined $opts->{value} ? delete $opts->{value} : $src->$k();

         $opts = $_field_options->( $schema, $result, $k, $opts );
         $opts = $_bind->( $k, $v, $opts );
      }

      $_push_field->( $f, $type, $opts );
   }

   return;
}

sub p_file ($@) {
   my $f = shift; return $_push_field->( $f, 'file', $_bind->( @_ ) );
}

sub p_hidden ($@) {
   my $f = shift; return $_push_field->( $f, 'hidden', $_bind->( @_ ) );
}

sub p_image ($@) {
   my ($f, $title, $href, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{href} = $href; $opts->{title} = $title,

   return $_push_field->( $f, 'image', $opts );
}

sub p_item ($@) {
   my ($f, $value, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{value} = $value;

   return $_push_to->( $f, $opts );
}

sub p_label ($@) {
   my ($f, $label, $content, $opts) = @_; $opts = { %{ $opts // {} } };

   $opts->{content} = $content; $opts->{label} = $label;

   return $_push_field->( $f, 'label', $opts );
}

sub p_link ($@) {
   my $f = shift; return $_push_to->( $f, f_link( @_ ) );
}

sub p_list ($@) {
   my ($f, $sep, $list, $opts) = @_;

   return p_container $f, $_f_list->( $sep, $list ), $opts;
}

sub p_password ($@) {
   my $f = shift; return $_push_field->( $f, 'password', $_bind->( @_ ) );
}

sub p_radio ($@) {
   my $f = shift; return $_push_field->( $f, 'radio', $_bind->( @_ ) );
}

sub p_row ($;$) {
   my ($table, $x) = @_;

   if (not $x or is_hashref $x->[ 0 ]) {
      push @{ $table->{rows} //= [] }, $x //= []; return $x;
   }

   return push @{ $table->{rows} //= [] }, @{ $x };
}

sub p_select ($@) {
   my $f = shift; return $_push_field->( $f, 'select', $_bind->( @_ ) );
}

sub p_slider ($@) {
   my $f = shift; return $_push_field->( $f, 'slider', $_bind->( @_ ) );
}

sub p_span ($@) {
   my $f = shift; return $_push_field->( $f, 'tag', f_tag( 'span', @_ ) );
}

sub p_table ($@) {
   my $f = shift; return $_push_field->( $f, 'table', @_ );
}

sub p_tag ($@) {
   my $f = shift; return $_push_field->( $f, 'tag', f_tag( @_ ) );
}

sub p_text ($@) {
   my $f = shift; return $_push_field->( $f, 'text', $_bind->( @_ ) );
}

sub p_textarea ($@) {
   my $f = shift; return $_push_field->( $f, 'textarea', $_bind->( @_ ) );
}

sub p_textfield ($@) {
   my $f = shift; return $_push_field->( $f, 'textfield', $_bind->( @_ ) );
}

sub p_unordered ($@) {
   my ($f, $opts) = @_; $opts = { %{ $opts // {} } }; $opts->{list} //= [];

   return $_push_field->( $f, 'unordered', $opts );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Form - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Form;
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
