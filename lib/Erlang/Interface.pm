package Erlang::Interface;

use strict;
use warnings;

use version; our $VERSION = qv('0.0.1');

use Carp;
use English qw(-no_match_vars);

use File::HomeDir;
use Path::Class;
use NetAddr::IP;
use Sys::Hostname;
use Data::UUID;

use Erlang::Interface::InlineC;
use Erlang::Interface::SockFD;
use Erlang::Interface::Eterm;

INIT {
    for my $method (qw(cookie address host alive node creation)) {
        no strict 'refs';    ## no critic
        *{__PACKAGE__ . q{::} . $method} = sub {
            return Erlang::Interface::InlineC->$method(shift);
          }
    }
}

sub new {
    my $class   = shift;
    my %arg_for = @_;

    for (qw(cookie address alive host creation)) {
        no strict 'subs';    ## no critic
        no strict 'refs';    ## no critic
        (_init_ . $_)->(\%arg_for);
    }

    return Erlang::Interface::InlineC::new_interface(map {$arg_for{$_}}
          qw(cookie address alive host creation));
}

sub _init_cookie {
    my ($arg_for) = @_;

    my $cookie = $arg_for->{cookie};
    return if $cookie;

    my $fh =
         Path::Class::File->new(File::HomeDir->my_home, '.erlang.cookie')->openr
      or croak $OS_ERROR;
    $cookie = $fh->getline;
    $fh->close or croak $OS_ERROR;

    $cookie =~ s/\n$//xm;
    croak '.erlang.cookie is empty.' if !$cookie;
    $arg_for->{cookie} = $cookie;

    return;
}

sub _init_address {
    my ($arg_for) = @_;

    my $address = $arg_for->{address} || '0.0.0.0';
    my $ip = NetAddr::IP->new($address) or croak 'address error.';
    $arg_for->{address} = $ip->addr();

    return;
}

sub _init_alive {
    my ($arg_for) = @_;
    $arg_for->{alive} ||= Data::UUID->new->create_str();
    return;
}

sub _init_host {
    my ($arg_for) = @_;
    $arg_for->{host} ||= hostname();
    return;
}

sub _init_creation {
    my ($arg_for) = @_;
    $arg_for->{creation} ||= int rand 32_768;
    return;
}

sub connect {    ## no critic
    my $self    = shift;
    my %arg_for = @_;

    _init_address(\%arg_for);
    croak 'alive error.' if !$arg_for{alive};

    return Erlang::Interface::InlineC::connect_and_get_sockfd(map {$arg_for{$_}}
          qw(address alive));
}

sub DESTROY {
    Erlang::Interface::InlineC::destroy_interface(shift);
    return;
}

1;
