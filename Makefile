# Local installs, for dogfooding neocaca as the everyday editor; packaging
# comes later. Every build is ReleaseSafe, as shipped, with link-time
# optimization; scripts/bolt.sh adds the profile-guided layout (llvm-bolt).
#
#   make                     ReleaseSafe with LTO, in zig-out/release
#   make install             that build, installed to $(PREFIX)/bin
#   make optimized           LTO, then BOLT trained on scripted sessions
#   make optimized-install   all of that in one go, then installed
#   make bolt-use FILE=x     edit with the instrumented build; quitting
#                            adds your session to the profiles
#   make bolt-optimize       lay the build out again from every profile
#   make bolt-compare        CPU time, LTO against LTO+BOLT (RUNS=5)
#   make uninstall
#   make clean               the builds here and every profile
#
# Run as yourself: installing asks for sudo (or doas) only to copy. DESTDIR
# stages the install only; zig build never sees it.
PREFIX ?= /usr/local
DESTDIR ?=
RUNS ?= 5
FILE ?=

release = zig-out/release/bin/neocaca

all:
	env -u DESTDIR zig build -Doptimize=safe -Dlto=full -p zig-out/release

install: all
	PREFIX=$(PREFIX) DESTDIR=$(DESTDIR) sh scripts/install.sh $(release)

optimized:
	sh scripts/bolt.sh

optimized-install: optimized
	PREFIX=$(PREFIX) DESTDIR=$(DESTDIR) sh scripts/install.sh "$$(sh scripts/bolt.sh path)"

bolt-use:
	sh scripts/bolt.sh use $(FILE)

bolt-optimize:
	sh scripts/bolt.sh optimize

bolt-compare:
	sh scripts/bolt.sh compare $(RUNS)

uninstall:
	PREFIX=$(PREFIX) DESTDIR=$(DESTDIR) sh scripts/install.sh --uninstall

clean:
	rm -rf zig-out/release zig-out/bolt

.PHONY: all install optimized optimized-install bolt-use bolt-optimize bolt-compare uninstall clean
