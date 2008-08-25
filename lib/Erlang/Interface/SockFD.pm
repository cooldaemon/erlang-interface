package Erlang::Interface::SockFD;

use strict;
use warnings;

use version; our $VERSION = qv('0.0.1');

use Carp;
use English qw(-no_match_vars);

use Erlang::Interface::InlineC;
use Erlang::Interface::Eterm;

sub self_pid {
    return Erlang::Interface::InlineC::make_self_pid(shift);
}

sub send {    ## no critic
    my ($self, $to, $message) = @_;

    for ($to, $message) {
        return if ref($_) ne 'Erlang::Interface::Eterm';
    }
    return if !$to->is_pid;

    return Erlang::Interface::InlineC::send_message($self, $to, $message,);
}

sub reg_send {
    my ($self, $to, $message) = @_;

    return if length($to) == 0;
    return if ref($message) ne 'Erlang::Interface::Eterm';

    return Erlang::Interface::InlineC::reg_send_message($self, $to, $message,);
}

sub receive {
    return Erlang::Interface::InlineC::receive_message(shift);
}

sub rpc {
    my ($self, $mod, $fun, $args) = @_;

    return if length($mod) == 0;
    return if length($fun) == 0;
    return if ref($args) ne 'Erlang::Interface::Eterm' || !$args->is_list;

    return Erlang::Interface::InlineC::rpc($self, $mod, $fun, $args,);
}

sub rpc_send {
    my ($self, $mod, $fun, $args,) = @_;

    return if length($mod) == 0;
    return if length($fun) == 0;
    return if ref($args) ne 'Erlang::Interface::Eterm' || !$args->is_list;

    return Erlang::Interface::InlineC::rpc_send($self, $mod, $fun, $args,);
}

sub rpc_receive {
    my ($self, $timeout,) = @_;

    if (defined $timeout) {
        return if $timeout !~ /^\d+$/xm;
    } else {
        $timeout = -1;    # ei.h : #define ERL_NO_TIMEOUT -1
    }

    my $result = Erlang::Interface::InlineC::rpc_receive($self, $timeout,);
    return if !$result || !$result->is_tuple || $result->size != 2;
    return ($result->value)[1];
}

sub DESTROY {
    Erlang::Interface::InlineC::destroy_sockfd(shift);
    return;
}

1;
