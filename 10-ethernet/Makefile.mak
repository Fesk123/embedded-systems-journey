CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -Wpedantic -std=c11

all: eth_ps_backend

eth_ps_backend: eth_ps_backend.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f eth_ps_backend

.PHONY: all clean