# 交叉编译静态 PID1。默认 aarch64 musl，可覆盖 CC。
CC      ?= aarch64-linux-musl-gcc
CFLAGS  ?= -Os -Wall -Wextra -Wno-unused-result
LDFLAGS ?= -static -s

all: harnoa-init

harnoa-init: harnoa-init.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f harnoa-init

.PHONY: all clean
