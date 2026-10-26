#!/bin/sh
# Builds the files a dogfood pass edits (docs/dogfooding.md), the same
# bytes every time, in an empty directory.
#
#   scripts/dogfood-corpus.sh DIR          # about 170 MB
#   BIG=1 scripts/dogfood-corpus.sh DIR    # also a 1 GB log
#
# POSIX sh and awk only. Run as a user who is not root, or the read-only
# and unreadable files are not what they claim to be.
set -eu

dir=${1:?usage: dogfood-corpus.sh DIR}
repo=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$dir"
[ -z "$(ls -A "$dir")" ] || { echo "dogfood-corpus.sh: $dir is not empty" >&2; exit 1; }
cd "$dir"

# Doubles a file until it reaches at least $2 bytes, then cuts it there
# and drops the line the cut split.
grow() {
	while [ "$(wc -c <"$1")" -lt "$2" ]; do
		cat "$1" "$1" >"$1.tmp" && mv "$1.tmp" "$1"
	done
	head -c "$2" "$1" | sed '$d' >"$1.tmp" && mv "$1.tmp" "$1"
}

# A real project to change: this repository, as committed.
git clone -q "$repo" repo

# A server log: timestamps, levels, the odd error and a stack trace.
awk 'BEGIN {
	for (i = 0; i < 20000; i++) {
		lvl = (i % 97 == 0) ? "ERROR" : (i % 13 == 0) ? "WARN" : "INFO"
		printf "2026-10-22T%02d:%02d:%02d.%03dZ %-5s req=%06d path=/api/v1/items/%d took=%dms\n",
			(i / 3600) % 24, (i / 60) % 60, i % 60, i % 1000, lvl, i, i % 500, (i * 7) % 900
		if (lvl == "ERROR")
			printf "    at handler (src/server.zig:%d)\n    at loop (src/main.zig:%d)\n", i % 400, i % 90
	}
}' >server.log
grow server.log 104857600
if [ "${BIG:-}" = 1 ]; then
	cp server.log huge.log
	grow huge.log 1073741824
fi

# Minified JSON: one 20 MB line.
awk 'BEGIN {
	printf "["
	for (i = 0; i < 340000; i++)
		printf "%s{\"id\":%d,\"name\":\"item %d\",\"tags\":[\"a\",\"b\"],\"ok\":%s}",
			(i ? "," : ""), i, i, (i % 2 ? "true" : "false")
	printf "]\n"
}' >minified.json

# A CSV with a header and a million rows, for column edits.
awk 'BEGIN {
	print "id,name,city,amount"
	for (i = 1; i <= 1000000; i++)
		printf "%d,name %d,city %d,%d.%02d\n", i, i % 977, i % 31, i % 10000, i % 100
}' >data.csv

# Files from other systems.
printf 'first line\r\nsecond line\r\nthird line\r\n' >windows.txt
printf '\357\273\277bom at the start\n' >bom.txt
printf 'no final newline' >no-final-newline.txt
printf 'all:\n\tzig build\n\ntest:\n\tzig build test\n' >Makefile

# Text the width code must get right: CJK, emoji with ZWJ and flags,
# combining marks, right-to-left, a tab, and a line wider than any window.
{
	printf 'wide: 日本語のテキスト\n'
	printf 'emoji: 👍🏽 👨‍👩‍👧 🇫🇷 ✔️\n'
	printf 'combining: e\314\201 a\314\212 n\314\203\n'
	printf 'rtl: مرحبا بالعالم\n'
	printf 'tab:\tafter a tab\n'
	awk 'BEGIN { for (i = 0; i < 2000; i++) printf "%d ", i; print "" }'
} >unicode.txt

# Hostile and binary content: escape sequences, NUL, invalid UTF-8, an
# executable.
printf 'title \033]0;owned\007 clear \033[2J red \033[31mred\033[0m nul \000 bad \377\376 c1 \302\233\n' >escapes.txt
cp "$repo/zig-out/bin/neocaca" binary 2>/dev/null || cp /bin/sh binary

# Paths that are not plain files.
ln -s unicode.txt link-to-unicode.txt
ln -s does-not-exist dangling-link.txt
ln unicode.txt hard-link-to-unicode.txt
printf 'read only\n' >read-only.txt
chmod 444 read-only.txt
printf 'secret\n' >unreadable.txt
chmod 000 unreadable.txt
mkdir a-directory

echo "dogfood corpus in $(pwd):"
ls -la
