package Erlang::Interface::Eterm;

use strict;
use warnings;

use version; our $VERSION = qv('0.0.1');

use Carp;
use English qw(-no_match_vars);

use Erlang::Interface::InlineC;

INIT {
    no strict 'refs';    ## no critic

    for (
        qw(
        int uint float atom pid port ref tuple binary list empty_list cons
        )
      )
    {
        my $method = 'is_' . $_;
        *{__PACKAGE__ . q{::} . $method} = sub {
            return Erlang::Interface::InlineC->$method(shift);
          }
    }

    for (qw(atom var string)) {
        my $method = 'make_' . $_;
        *{__PACKAGE__ . q{::} . $method} = sub {
            my ($class, $string) = @_;
            return if length($string) == 0;
            return Erlang::Interface::InlineC->$method($string);
          }
    }
}

sub type {
    my ($self) = @_;

    for (
        qw(
        int uint float
        atom pid port ref tuple binary
        empty_list string list cons
        )
      )
    {
        my $method = 'is_' . $_;
        return $_ if $self->$method;
    }
    return;
}

sub make_binary {
    my ($class, $binary) = @_;

    return if length($binary) == 0;
    return Erlang::Interface::InlineC::make_binary($binary, length($binary),);
}

sub make_float {
    my ($class, $float) = @_;

    return if $float !~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/xm;
    return Erlang::Interface::InlineC::make_float($float);
}

sub make_int {
    my ($class, $int) = @_;

    return if $int !~ /^-?\d+$/xm;
    return Erlang::Interface::InlineC::make_int($int);
}

sub make_uint {
    my ($class, $int) = @_;

    return if $int !~ /^\d+$/xm;
    return Erlang::Interface::InlineC::make_uint($int);
}

sub make_list {
    my ($class, @elems) = @_;

    return Erlang::Interface::InlineC::make_empty_list()
      if @elems == 0;

    for (@elems) {
        return if ref($_) ne __PACKAGE__;
    }

    return Erlang::Interface::InlineC::make_list(\@elems);
}

sub make_tuple {
    my ($class, @elems) = @_;

    return if !@elems;

    for (@elems) {
        return if ref($_) ne __PACKAGE__;
    }

    return Erlang::Interface::InlineC::make_tuple(\@elems);
}

sub make_pid {
    my ($class, $node, $number, $serial, $creation) = @_;

    return if length($node) == 0;
    return if $number !~ /^\d+$/xm;
    return if $serial !~ /^\d+$/xm;
    return if $creation !~ /^\d+$/xm;

    return Erlang::Interface::InlineC::make_pid($node, $number, $serial,
        $creation,);
}

sub make_port {
    my ($class, $node, $number, $creation) = @_;

    return if length($node) == 0;
    return if $number !~ /^\d+$/xm;
    return if $creation !~ /^\d+$/xm;

    return Erlang::Interface::InlineC::make_port($node, $number, $creation,);
}

sub make_ref {
    my ($class, $node, $n1, $n2, $n3, $creation) = @_;

    return if length($node) == 0;
    return if $n1 !~ /^\d+$/xm;
    return if $n2 !~ /^\d+$/xm;
    return if $n3 !~ /^\d+$/xm;
    return if $creation !~ /^\d+$/xm;

    return Erlang::Interface::InlineC::make_ref($node, $n1, $n2, $n3, $creation,
    );
}

sub copy {
    return Erlang::Interface::InlineC::copy(shift);
}

sub is_string {
    my ($self) = @_;

    return if !$self->is_list;

    my $target = $self;
    while ($target->is_empty_list) {
        my $head = Erlang::Interface::InlineC::cons_head($target);
        return if !$head->is_int;
        $target = Erlang::Interface::InlineC::cons_tail($target);
    }

    return 1;
}

sub value {
    my ($self) = @_;

    return Erlang::Interface::InlineC::int_value($self)
      if $self->is_int;
    return Erlang::Interface::InlineC::uint_value($self)
      if $self->is_uint;
    return Erlang::Interface::InlineC::float_value($self)
      if $self->is_float;

    return Erlang::Interface::InlineC::atom_ptr($self)
      if $self->is_atom;
    return Erlang::Interface::InlineC::binary_ptr($self)
      if $self->is_binary;
    return Erlang::Interface::InlineC::list_to_ptr($self)
      if $self->is_string;

    return (
        Erlang::Interface::InlineC::pid_node($self),
        Erlang::Interface::InlineC::pid_number($self),
        Erlang::Interface::InlineC::pid_serial($self),
        Erlang::Interface::InlineC::pid_creation($self),
    ) if $self->is_pid;

    return (
        Erlang::Interface::InlineC::port_node($self),
        Erlang::Interface::InlineC::port_number($self),
        Erlang::Interface::InlineC::port_creation($self),
    ) if $self->is_port;

    return (
        Erlang::Interface::InlineC::ref_numbers($self),
        Erlang::Interface::InlineC::ref_len($self),
        Erlang::Interface::InlineC::ref_creation($self),
    ) if $self->is_ref;

    if ($self->is_tuple) {
        return
          map {Erlang::Interface::InlineC::tuple_element($self, $_);}
          (1 .. Erlang::Interface::InlineC::tuple_size($self));
    }

    if ($self->is_list) {
        my @eterms;
        my $target = $self;
        while (Erlang::Interface::InlineC::is_empty_list($target)) {
            push @eterms, Erlang::Interface::InlineC::cons_head($target);
            $target = Erlang::Interface::InlineC::cons_tail($target);
        }
        return @eterms;
    }

    return;
}

sub size {
    my ($self) = @_;

    return Erlang::Interface::InlineC::atom_size($self)
      if $self->is_atom;
    return Erlang::Interface::InlineC::binary_size($self)
      if $self->is_binary;
    return Erlang::Interface::InlineC::tuple_size($self)
      if $self->is_tuple;
    return Erlang::Interface::InlineC::list_size($self)
      if $self->is_list;

    return;
}

sub DESTROY {
    Erlang::Interface::InlineC::destroy_eterm(shift);
    return;
}

1;
