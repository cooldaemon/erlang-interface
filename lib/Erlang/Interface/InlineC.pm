package Erlang::Interface::InlineC;

use strict;
use warnings;

use version; our $VERSION = qv('0.0.1');

use Inline C => Config    ## no critic
  => CCFLAGS => '-std=c99' => LIBS =>
  '-L/opt/local/lib/erlang/lib/erl_interface-3.5.5.3/lib -lerl_interface -lei'
  => INC => '-I/opt/local/lib/erlang/lib/erl_interface-3.5.5.3/include';

{
    no strict 'subs';     ## no critic
    use Inline C;
}

INIT {
    init();
}

1;

__DATA__
__C__

#include "erl_interface.h"
#include "ei.h"

extern const char *erl_thisnodename(void);
extern short erl_thiscreation(void);
#define SELF(fd) erl_mk_pid(erl_thisnodename(), fd, 0, erl_thiscreation())

static SV* _new_sockfd(int);
static SV* _new_eterm(ETERM*);

typedef struct {
    char* address;
} Interface;

typedef struct {
    int sockfd;
} SockFD;

void init() {
    erl_init(NULL, 0);
}

SV* new_interface(
    char* cookie, char* address, char* alive, char* host, short creation
) {
    struct in_addr addr;
    addr.s_addr = inet_addr(address);

    char node[strlen(alive) + strlen(host) + 1]; 
    sprintf(node, "%s@%s", alive, host);

    if (!erl_connect_xinit(host, alive, node, &addr, cookie, creation))
        croak("%s init failed.", node);

    Interface* eif = malloc(sizeof(Interface));
    eif->address  = strdup(address);

    SV *obj_ref = newSViv(0);
    SV *obj = newSVrv(obj_ref, "Erlang::Interface");
    sv_setiv(obj, (IV)eif);
    SvREADONLY_on(obj);
    return obj_ref;
}

void destroy_interface(SV* obj) {
    Interface* eif = (Interface*)SvIV(SvRV(obj));

    free(eif->address);
    free(eif);
}

static SV* _new_sockfd(int sockfd) {
    SockFD* sfd = malloc(sizeof(SockFD));
    sfd->sockfd = sockfd;

    SV *obj_ref = newSViv(0);
    SV *obj = newSVrv(obj_ref, "Erlang::Interface::SockFD");
    sv_setiv(obj, (IV)sfd);
    SvREADONLY_on(obj);
    return obj_ref; 
}

void destroy_sockfd(SV* obj) {
    SockFD* sfd = (SockFD*)SvIV(SvRV(obj));
    free(sfd);
}

static SV* _new_eterm(ETERM* eterm) {
    SV* obj_ref = newSViv(0);
    SV* obj = newSVrv(obj_ref, "Erlang::Interface::Eterm");

    sv_setiv(obj, (IV)eterm);
    SvREADONLY_on(obj);
    return obj_ref;
}

void destroy_eterm(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    erl_free_term(eterm);
}

char* cookie(char *class, SV* obj) {
    return erl_thiscookie();
}

char* address(char *class, SV* obj) {
    return ((Interface*)SvIV(SvRV(obj)))->address;
}

char* alive(char *class, SV* obj) {
    return erl_thisalivename();
}

char* host(char *class, SV* obj) {
    return erl_thishostname();
}

char* node(char *class, SV* obj) {
    return erl_thisnodename();
}

short creation(char *class, SV* obj) {
    return erl_thiscreation();
}

SV* connect_and_get_sockfd(char *address, char *alive) {
    struct in_addr addr;
    addr.s_addr = inet_addr(address);

    int sockfd;
    if ((sockfd = erl_xconnect(&addr, alive)) < 0)
        croak("connect failed.");

    return _new_sockfd(sockfd);
}

int send_message(SV* obj, SV *to, SV* message) {
    SockFD* sfd           = (SockFD*)SvIV(SvRV(obj));
    ETERM*  to_eterm      = (ETERM*)SvIV(SvRV(to));
    ETERM*  message_eterm = (ETERM*)SvIV(SvRV(message));

    return erl_send(sfd->sockfd, to_eterm, message_eterm);
}

int reg_send_message(SV* obj, char *to, SV* message) {
    SockFD* sfd           = (SockFD*)SvIV(SvRV(obj));
    ETERM*  message_eterm = (ETERM*)SvIV(SvRV(message));

    return erl_reg_send(sfd->sockfd, to, message_eterm);
}

SV* receive_message(SV* obj) {
    SockFD* sfd = (SockFD*)SvIV(SvRV(obj));

    int            size = 1024;
    unsigned char* buf = malloc(size);
    ErlMessage     emsg;
    SV*            message;

    if (erl_xreceive_msg(sfd->sockfd, &buf, &size, &emsg) == ERL_MSG) {
        message = _new_eterm(emsg.msg);
        erl_free_term(emsg.to);
    } else {
        message = newSViv(0);
    }

    free(buf);
    return message;
}

SV* rpc(SV* obj, char *mod, char *fun, SV* args) {
    SockFD* sfd = (SockFD*)SvIV(SvRV(obj));
    ETERM*  args_eterm = (ETERM*)SvIV(SvRV(args));

    ETERM* result = erl_rpc(sfd->sockfd, mod, fun, args_eterm);
    if (result == NULL) return newSViv(0);
    return _new_eterm(result);
}

int rpc_send(SV* obj, char *mod, char *fun, SV* args) {
    SockFD* sfd = (SockFD*)SvIV(SvRV(obj));
    ETERM*  args_eterm = (ETERM*)SvIV(SvRV(args));

    int result = erl_rpc_to(sfd->sockfd, mod, fun, args_eterm);
    if (result == 0) return 1;
    return 0;
}

SV* rpc_receive(SV* obj, int timeout) {
    SockFD* sfd = (SockFD*)SvIV(SvRV(obj));

    ErlMessage emsg;
    if (erl_rpc_from(sfd->sockfd, timeout, &emsg) == ERL_MSG) {
        erl_free_term(emsg.to);
        return _new_eterm(emsg.msg);
    } else {
        return newSViv(0);
    }
}

SV* make_atom(char* class, char* string) {
    return _new_eterm(erl_mk_atom(string));
}

SV* make_binary(char* bptr, int size) {
    return _new_eterm(erl_mk_binary(bptr, size));
}

SV* make_var(char* class, char* name) {
    return _new_eterm(erl_mk_var(name));
}

SV* make_string(char* class, char* string) {
    return _new_eterm(erl_mk_string(string));
}

SV* make_float(char *class, double f) {
    return _new_eterm(erl_mk_float(f));
}

SV* make_int(int n) {
    return _new_eterm(erl_mk_int(n));
}

SV* make_uint(int n) {
    return _new_eterm(erl_mk_int((unsigned int)n));
}

SV* make_empty_list() {
    return _new_eterm(erl_mk_empty_list());
}

SV* make_list(SV* array_ref) {
    AV* array = (AV*)SvRV(array_ref);
    int size = av_len(array);

    ETERM* eterm_array[size+1];
    for (int i = 0; i <= size; i++) {
        SV** elem = av_fetch(array, i, 0);
        eterm_array[i] = (ETERM*)SvIV(SvRV(*elem));
    }

    return _new_eterm(erl_mk_list(&eterm_array, size+1));
}

SV* make_tuple(SV* array_ref) {
    AV* array = (AV*)SvRV(array_ref);
    int size = av_len(array);

    ETERM* eterm_array[size+1];
    for (int i = 0; i <= size; i++) {
        SV** elem = av_fetch(array, i, 0);
        eterm_array[i] = (ETERM*)SvIV(SvRV(*elem));
    }

    return _new_eterm(erl_mk_tuple(&eterm_array, size+1));
}

SV* make_pid(char* node, int number, int serial, int creation) {
    return _new_eterm(erl_mk_pid(
        (const char*)node,
        (unsigned int)number,
        (unsigned int)serial,
        (unsigned int)creation
    ));
}

SV* make_self_pid(SV* obj) {
    SockFD* sfd = (SockFD*)SvIV(SvRV(obj));
    return _new_eterm(erl_mk_pid(
        erl_thisnodename(), sfd->sockfd, 0, erl_thiscreation()
    ));
}

SV* make_port(char *node, int number, int creation) {
    return _new_eterm(erl_mk_port(
        (const char*)node,
        (unsigned int)number,
        (unsigned int)creation
    ));
}

// n1*2^64 + n2*2^32 + n3
SV* make_ref(char* node, int n1, int n2, int n3, int creation) {
    return _new_eterm(erl_mk_long_ref(
        (const char*)node,
        (unsigned int)n1,
        (unsigned int)n2,
        (unsigned int)n3,
        (unsigned int)creation
    ));
}

SV* cons(SV* head, SV* tail) {
    ETERM* head_eterm = (ETERM*)SvIV(SvRV(head));
    ETERM* tail_eterm = (ETERM*)SvIV(SvRV(tail));
    return _new_eterm(erl_cons(head_eterm, tail_eterm));
}

SV* copy(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return _new_eterm(erl_copy_term(eterm));
}

int is_int(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_INTEGER(eterm);
}

int is_uint(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_UNSIGNED_INTEGER(eterm);
}

int is_float(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_FLOAT(eterm);
}

int is_atom(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_ATOM(eterm);
}

int is_pid(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_PID(eterm);
}

int is_port(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_PORT(eterm);
}

int is_ref(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_REF(eterm);
}

int is_tuple(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_TUPLE(eterm);
}

int is_binary(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_BINARY(eterm);
}

int is_list(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_LIST(eterm);
}

int is_empty_list(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_EMPTY_LIST(eterm);
}

int is_cons(char* class, SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_IS_CONS(eterm);
}

char* atom_ptr(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_ATOM_PTR(eterm);
}

int atom_size(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_ATOM_SIZE(eterm);
}

char* binary_ptr(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return (char*)ERL_BIN_PTR(eterm);
}

int binary_size(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_BIN_SIZE(eterm);
}

int int_value(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_INT_VALUE(eterm);
}

int uint_value(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return (int)ERL_INT_UVALUE(eterm);
}

double float_value(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_FLOAT_VALUE(eterm);
}

SV* pid_node(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return _new_eterm(ERL_PID_NODE(eterm));
}

int pid_number(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_PID_NUMBER(eterm);
}

int pid_serial(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_PID_SERIAL(eterm);
}

int pid_creation(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_PID_CREATION(eterm);
}

SV* port_node(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return _new_eterm(ERL_PORT_NODE(eterm));
}

int port_number(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_PORT_NUMBER(eterm);
}

int port_creation(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_PORT_CREATION(eterm);
}

int ref_number(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_REF_NUMBER(eterm);
}

int ref_numbers(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_REF_NUMBERS(eterm);
}

int ref_len(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_REF_LEN(eterm);
}

int ref_creation(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_REF_CREATION(eterm);
}

SV* tuple_element(SV *obj, int position) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return _new_eterm(erl_element(position, eterm));
}

int tuple_size(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return ERL_TUPLE_SIZE(eterm);
}

SV* cons_head(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return _new_eterm(ERL_CONS_HEAD(eterm));
}

SV* cons_tail(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return _new_eterm(ERL_CONS_TAIL(eterm));
}

int list_to_binary(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return _new_eterm(erl_iolist_to_binary(eterm));
}

char* list_to_ptr(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return erl_iolist_to_string(eterm);
}

int list_size(SV* obj) {
    ETERM* eterm = (ETERM*)SvIV(SvRV(obj));
    return erl_length(eterm);
}
