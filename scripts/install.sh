#!/bin/sh
# Installs a built neocaca binary system-wide, for local use; packaging
# comes later.
#
#   scripts/install.sh BINARY     # copies BINARY to $PREFIX/bin/neocaca
#   scripts/install.sh --uninstall
#
# Run it as yourself: it asks for root (sudo or doas) only to copy, so the
# build directories stay yours. PREFIX (default /usr/local) and DESTDIR
# (staging) are honored.
set -eu

PREFIX=${PREFIX:-/usr/local}
DESTDIR=${DESTDIR:-}
bindir=$DESTDIR$PREFIX/bin

case ${1:-} in
"")
	echo "usage: install.sh BINARY | --uninstall" >&2
	exit 2
	;;
-h | --help)
	sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
	;;
esac

# Root only when the nearest existing directory is not ours to write.
target=$bindir
while [ ! -e "$target" ]; do target=$(dirname "$target"); done
as_root=
if [ ! -w "$target" ]; then
	for tool in sudo doas; do
		command -v "$tool" >/dev/null 2>&1 && as_root=$tool && break
	done
	[ -n "$as_root" ] || {
		echo "install.sh: $bindir is not writable; run as root" >&2
		exit 1
	}
	echo "Installing to $bindir needs root; asking $as_root."
fi

if [ "$1" = --uninstall ]; then
	$as_root rm -f "$bindir/neocaca"
	echo "Removed $bindir/neocaca"
	exit 0
fi

[ -x "$1" ] || {
	echo "install.sh: no binary at $1" >&2
	exit 1
}
# install(1) replaces the file instead of writing into it, so a running
# neocaca keeps its old binary.
$as_root install -D -m 755 "$1" "$bindir/neocaca"
echo "Installed $bindir/neocaca ($("$bindir/neocaca" --version))"
