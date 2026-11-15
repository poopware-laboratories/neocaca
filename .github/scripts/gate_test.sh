#!/bin/sh
# Tests gate.sh against a fake `gh` that prints one
# scripted listing per call (listing.1, listing.2, ...; the last repeats).
# Usage: .github/scripts/gate_test.sh [path/to/gate.sh]
set -u
gate=$(realpath "${1:-$(dirname "$0")/gate.sh}")
here=$(mktemp -d)
trap 'rm -rf "$here"' EXIT
pass=0
fail=0

mkdir -p "$here/bin"
cat >"$here/bin/gh" <<'EOF'
#!/bin/sh
n=$(cat "$CASE/calls" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$CASE/calls"
f="$CASE/listing.$n"
[ -f "$f" ] || f=$(ls "$CASE"/listing.* | sort -t. -k2 -n | tail -1)
cat "$f"
EOF
chmod +x "$here/bin/gh"

tab=$(printf '\t')
# check NAME WANT_EXIT WANT_TEXT LISTING...
check() {
	name=$1 want=$2 text=$3
	shift 3
	# Read by the fake `gh`.
	CASE=$(mktemp -d)
	export CASE
	i=0
	for l in "$@"; do
		i=$((i + 1))
		printf '%b' "$l" >"$CASE/listing.$i"
	done
	summary="$CASE/summary"
	out=$(PATH="$here/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 \
		POLL_SECONDS=0 GITHUB_STEP_SUMMARY="$summary" sh "$gate" 2>&1)
	got=$?
	if [ "$got" = "$want" ] && printf '%s\n%s' "$out" "$(cat "$CASE/summary" 2>/dev/null)" | grep -q -- "$text"; then
		pass=$((pass + 1))
		echo "ok   $name"
	else
		fail=$((fail + 1))
		echo "FAIL $name (exit $got, want $want; no \"$text\")"
		printf '%s\n' "$out" | sed 's/^/     /'
	fi
	rm -rf "$CASE"
}

s="completed${tab}success"
check "all passed" 0 "every required job passed" \
	"fmt${tab}$s\ntest (ubuntu-latest, debug)${tab}$s\nci${tab}in_progress${tab}\n"
check "a failure fails the gate" 1 "::error title=Required job did not pass::cross (x86_64-macos) ended as failure" \
	"fmt${tab}$s\ncross (x86_64-macos)${tab}completed${tab}failure\n"
check "a cancelled job fails it" 1 "ended as cancelled" \
	"fmt${tab}$s\nbench${tab}completed${tab}cancelled\n"
check "a skipped job passes" 0 "| ratio | ⏭️ skipped |" \
	"fmt${tab}$s\nratio${tab}completed${tab}skipped\n"
check "the optional job may fail" 0 "every required job passed" \
	"fmt${tab}$s\nzig-latest${tab}completed${tab}failure\n"
check "the gate does not wait for itself" 0 "every required job passed" \
	"fmt${tab}$s\nci${tab}in_progress${tab}\n"
check "it waits for a pending job" 0 "waiting for 1 of 2 jobs" \
	"fmt${tab}$s\nbench${tab}in_progress${tab}\n" \
	"fmt${tab}$s\nbench${tab}$s\n"
check "it waits for a queued job, then fails with it" 1 "bench ended as failure" \
	"fmt${tab}$s\nbench${tab}queued${tab}\n" \
	"fmt${tab}$s\nbench${tab}completed${tab}failure\n"
check "it reads again until the run is set up" 0 "waiting for 0 of 0 jobs" \
	"" \
	"fmt${tab}$s\n"
check "the summary marks a pass" 0 "| fmt | ✅ success |" \
	"fmt${tab}$s\n"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
