#!/bin/sh
# Profile-guided layout for local installs: builds neocaca in ReleaseSafe
# with link-time optimization, instruments it with llvm-bolt, trains it on
# scripted editing sessions in tmux, and lays it out again for the code the
# training ran (hot blocks and functions together, cold ones split off).
# Zig 0.17 takes no compiler profile (no -fprofile-use), so this is where
# profiles guide the build. Linux on x86-64 or AArch64 only.
#
#   scripts/bolt.sh            # build, instrument, train, optimize
#   scripts/bolt.sh base       # the LTO build with relocations only
#   scripts/bolt.sh train      # profile the scripted sessions afresh
#   scripts/bolt.sh use [ARGS] # edit with the instrumented build; quitting
#                              # adds your session to the profiles
#   scripts/bolt.sh optimize   # lay the build out from every profile so far
#   scripts/bolt.sh compare [RUNS]
#                              # CPU time of the scripted sessions, LTO
#                              # build against the optimized one (perf)
#   scripts/bolt.sh path       # print the optimized binary's path
#   scripts/bolt.sh clean      # forget all profiles
#
# Each training replaces the last one's profiles; the sessions of `use` add
# up. All of them go when the LTO build changes: their addresses name the
# old code. Needs zig, llvm-bolt, merge-fdata and tmux;
# LLVM_BOLT and MERGE_FDATA name the tools when they carry a version suffix
# (Debian's llvm-bolt-18).
set -eu

caller=$PWD
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
out=$root/zig-out/bolt
base=$out/base/bin/neocaca
instrumented=$out/instrumented
profiles=$out/profiles
optimized=$out/neocaca
llvm_bolt=${LLVM_BOLT:-llvm-bolt}
merge_fdata=${MERGE_FDATA:-merge-fdata}
# Seconds between keys: the editor draws a frame for each, as for a person.
pause=${BOLT_PAUSE:-0.02}

need() {
	for tool in "$@"; do
		command -v "$tool" >/dev/null 2>&1 || {
			echo "bolt.sh: needs $tool" >&2
			exit 1
		}
	done
}

# The LTO build. A changed binary drops the profiles taken of the old one.
build_base() {
	# Not into DESTDIR, which zig build honors and make may export.
	env -u DESTDIR zig build -Doptimize=safe -Dlto=full -Demit-relocs=true -p "$out/base"
	mkdir -p "$profiles"
	sum=$(cksum <"$base")
	if [ "$(cat "$profiles/base.cksum" 2>/dev/null)" != "$sum" ]; then
		rm -rf "$profiles" "$instrumented"
		mkdir -p "$profiles"
		echo "$sum" >"$profiles/base.cksum"
	fi
}

instrument() {
	need "$llvm_bolt"
	build_base
	[ -x "$instrumented" ] && return
	"$llvm_bolt" "$base" -o "$instrumented" -instrument \
		-instrumentation-file="$profiles/neocaca" -instrumentation-file-append-pid
}

# One tmux server of our own, without the user's configuration.
sock=neocaca-bolt-$$
tm() {
	tmux -L "$sock" -f /dev/null "$@"
}

# Types each argument, pausing after each: one character as it is, a
# longer one as tmux key names (Enter, Escape, C-d, M-s) or, when it names
# no key, as its text. Escape
# waits out the editor's Escape timeout, or the next key would arrive as
# Alt plus that key.
keys() {
	for key in "$@"; do
		case $key in
		';') tm send-keys -t train -l '\;' ;; # alone, tmux's command separator
		?) tm send-keys -t train -l "$key" ;;
		*) tm send-keys -t train "$key" ;;
		esac
		case $key in Escape) sleep 0.1 ;; *) sleep "$pause" ;; esac
	done
}

# Types text as it is, a character at a time.
text() {
	printf '%s\n' "$1" | fold -w 1 | while IFS= read -r ch; do
		if [ -n "$ch" ]; then keys "$ch"; fi
	done
}

# Runs `$bin` on file $1 in a 120x40 pane, plays session $2, and waits for
# the editor to quit (each session ends with :q! or :wq).
session() {
	tm new-session -d -s train -x 120 -y 40 -c "$out/train" "$wrap $bin $1"
	sleep 0.3
	"$2"
	tries=0
	while tm has-session -t train 2>/dev/null; do
		tries=$((tries + 1))
		if [ "$tries" -gt 300 ]; then
			echo "bolt.sh: session $2 did not quit; screen:" >&2
			tm capture-pane -t train -p >&2
			tm kill-server
			exit 1
		fi
		sleep 0.1
	done
}

# The sessions: moves, searches, multiple selections, verbs, undo, insert
# typing and saves over source code, a log, a CSV and wide text.
code() {
	keys j j j j w w w b e e x x C-d C-d C-d C-u C-f C-b ge gg 120g vc
	keys / f n Space Enter n n n n N n M-n '*' n
	keys x X X M-s s c o n s t Enter c; text "let"; keys Escape u U u ,
	keys gg o; text "    const answer: u32 = 42; // trained"; keys Enter
	text "fn main() void {}"; keys Escape x y p P '>' '<' M-j '~' '`' u u u u
	keys % s '\w+' Enter ';' M-, ',' gg w d u w w c; text "renamed"; keys Escape
	keys 40j m m x d u M-i '(' M-a '{' r z u
	keys : w Enter : q '!' Enter
}

log() {
	keys ge gg / E R R O R Enter n n n n n n n n C-f C-f C-f C-f C-f C-f
	keys 2000g x X X X X X s t o o k = '\d+' Enter d u , 5000g vt vj vj vk
	keys ? W A R N Enter M-n M-n C-u C-u gg : 1 0 0 0 Enter x
	keys : q '!' Enter
}

csv() {
	keys x 300X M-s f , t , c; text "city"; keys Escape u ,
	keys 1000g X 200X s '\d+\.\d+' Enter y gg P u M-x
	keys gg 100X M-s A; text ",new"; keys Escape U u : q '!' Enter
}

wide() {
	keys w w e b l l l h h x J J M-j u
	keys / 世 Enter n i; text "漢字 é ﬁ "; keys Escape
	keys gg 5X M-s gl a; text " ✓"; keys Escape u
	keys : w q Enter
}

typing() {
	keys i
	for para in 1 2 3; do
		text "Paragraph $para: plain words typed one by one, as a person types."
		keys Enter Tab
		text "if (x) { return y; } // done"
		keys BSpace BSpace BSpace BSpace Enter Enter
	done
	keys Escape gg c; text "Notes"; keys Escape : w q Enter
}

# The same files every time, made fresh for each run.
corpus() {
	rm -rf "$out/train"
	mkdir -p "$out/train"
	cat src/*.zig src/*/*.zig >"$out/train/code.zig"
	awk 'BEGIN {
		for (i = 0; i < 100000; i++) {
			lvl = (i % 97 == 0) ? "ERROR" : (i % 13 == 0) ? "WARN" : "INFO"
			printf "2026-10-22T%02d:%02d:%02d.%03dZ %-5s req=%06d took=%dms\n",
				(i / 3600) % 24, (i / 60) % 60, i % 60, i % 1000, lvl, i, (i * 7) % 900
		}
	}' >"$out/train/server.log"
	awk 'BEGIN {
		print "id,name,city,amount"
		for (i = 1; i <= 20000; i++)
			printf "%d,name %d,city %d,%d.%02d\n", i, i % 977, i % 31, i % 10000, i % 100
	}' >"$out/train/data.csv"
	awk 'BEGIN {
		for (i = 0; i < 400; i++)
			printf "%d 世界 café ﬁle naïve e\314\201 日本語 tab\there 🎉 end\n", i
	}' >"$out/train/wide.txt"
}

# Plays every session on binary $1, each wrapped in `$2`.
play() {
	need tmux
	bin=$1
	wrap=${2:-}
	corpus
	trap 'tm kill-server 2>/dev/null || true' EXIT
	for s in code log csv wide typing; do
		file=$s.txt
		case $s in code) file=code.zig ;; log) file=server.log ;; csv) file=data.csv ;; typing) file=notes.txt ;; esac
		session "$file" "$s"
	done
}

# Every profile taken so far: the training's and those of `use`.
fdata() {
	find "$profiles" -name '*.fdata'
}

# The training's profiles go to profiles/scripted, replacing the last ones,
# so training again does not outweigh the sessions of `use`.
train() {
	instrument
	touch "$out/train.start"
	play "$instrumented"
	rm -rf "$profiles/scripted"
	mkdir -p "$profiles/scripted"
	find "$profiles" -maxdepth 1 -name '*.fdata' -newer "$out/train.start" \
		-exec mv {} "$profiles/scripted/" \;
	echo "bolt.sh: $(fdata | wc -l) profiles, $(find "$profiles" -maxdepth 1 -name '*.fdata' | wc -l) of them from use"
}

optimize() {
	need "$llvm_bolt" "$merge_fdata"
	[ -n "$(fdata)" ] || {
		echo "bolt.sh: no profiles yet; run 'scripts/bolt.sh train' first" >&2
		exit 1
	}
	fdata | xargs "$merge_fdata" >"$out/merged.fdata"
	# The debug sections are rewritten too, so panics still name the right
	# lines; nothing is stripped, for the same reason.
	"$llvm_bolt" "$base" -o "$optimized" -data="$out/merged.fdata" \
		-reorder-blocks=ext-tsp -reorder-functions=cdsort -split-functions \
		-split-all-cold -split-eh -icf=1 -use-gnu-stack -update-debug-sections
	echo "Optimized build: $optimized"
}

# Medians (and min-max) of the editor's CPU time over the sessions, which
# leaves out the pauses between keys.
compare() {
	need perf
	runs=${1:-5}
	[ -x "$optimized" ] || {
		echo "bolt.sh: no optimized build; run 'scripts/bolt.sh' first" >&2
		exit 1
	}
	echo "| build | CPU ms, median | min-max |"
	echo "|---|---|---|"
	for binary in "$base" "$optimized"; do
		rm -f "$out/stat."*
		n=0
		while [ "$n" -lt "$runs" ]; do
			n=$((n + 1))
			play "$binary" "perf stat -x, -e task-clock -o $out/stat.$n.\$\$ --" >/dev/null
		done
		# One total per run: the sessions' task-clock added up.
		for n in $(seq "$runs"); do
			cat "$out/stat.$n."* | awk -F, '$3 ~ /task-clock/ { t += $1 } END { printf "%.0f\n", t }'
		done | sort -n | awk -v name="${binary#"$root"/}" '
			{ v[NR] = $1 }
			END { m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
				printf "| `%s` | %.0f | %d-%d |\n", name, m, v[1], v[NR] }'
	done
	rm -f "$out/stat."*
}

command=${1:-all}
[ $# -gt 0 ] && shift
case $command in
all)
	train
	optimize
	;;
base) build_base ;;
train) train ;;
use)
	instrument
	cd "$caller"
	"$instrumented" "$@"
	;;
optimize) optimize ;;
compare) compare "$@" ;;
path) echo "$optimized" ;;
clean) rm -rf "$profiles" "$instrumented" "$out/merged.fdata" "$optimized" "$out/train" "$out/train.start" ;;
-h | --help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' ;;
*)
	echo "bolt.sh: unknown command: $command (try --help)" >&2
	exit 2
	;;
esac
