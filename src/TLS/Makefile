LUA_INC=/data/data/com.termux/files/usr/include/lua5.4
LUA_LIB=/data/data/com.termux/files/usr/lib

CFLAGS=-O2 -fPIC -I$(LUA_INC)
LDFLAGS=-shared -L$(LUA_LIB) -llua5.4 -lmbedtls -lmbedx509 -lmbedcrypto

all: tls.so

tls.so: tls.c
	clang $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f tls.so
