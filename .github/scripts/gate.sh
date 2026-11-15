#!/bin/sh
# The `ci` gate, the one CI check `main` requires. It starts with the other
# jobs of its workflow run, waits for them through the Actions API, and
# passes only when each succeeded or was skipped by its own `if`. Starting
# at once keeps the required check "in progress" from the first minute,
# where a gate that `needs` every job reports nothing ("Expected - Waiting
# for status to be reported") until the slowest one ends. A job added or
# renamed later is waited for without changing this script.
#
# Not waited for: the gate itself (GATE_NAME, default `ci`) and the jobs in
# OPTIONAL_JOBS (default `zig-latest`), which may fail. Needs GH_TOKEN with
# `actions: read`, GITHUB_REPOSITORY and GITHUB_RUN_ID; writes a table of
# the results to GITHUB_STEP_SUMMARY when set.
set -eu

: "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}"
self=${GATE_NAME:-ci}
optional=" ${OPTIONAL_JOBS:-zig-latest} "
interval=${POLL_SECONDS:-15}
# The jobs a run of this workflow starts with; a listing without them is
# one taken before the run was set up, and is read again.
expected=${EXPECTED_JOBS:-fmt}

# Every job of the run but the gate and the optional ones, as
# "name<TAB>status<TAB>conclusion", the latest attempt of each.
others() {
	gh api --paginate \
		"repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs?filter=latest&per_page=100" \
		--jq '.jobs[] | [.name, .status, (.conclusion // "")] | @tsv' |
		awk -F '\t' -v self="$self" -v opt="$optional" \
			'$1 != self && index(opt, " " $1 " ") == 0'
}

while :; do
	jobs=$(others)
	ready=yes
	for name in $expected; do
		printf '%s\n' "$jobs" | cut -f1 | grep -qx "$name" || ready=no
	done
	pending=$(printf '%s\n' "$jobs" | awk -F '\t' 'NF && $2 != "completed"' | wc -l)
	if [ "$ready" = yes ] && [ "$pending" -eq 0 ]; then break; fi
	echo "waiting for $pending of $(printf '%s\n' "$jobs" | awk 'NF' | wc -l) jobs"
	sleep "$interval"
done

failed=$(printf '%s\n' "$jobs" | awk -F '\t' 'NF && $3 != "success" && $3 != "skipped"')

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Required jobs"
		echo
		echo "| Job | Result |"
		echo "|-----|--------|"
		printf '%s\n' "$jobs" | awk -F '\t' 'NF {
			mark = ($3 == "success") ? "✅" : ($3 == "skipped") ? "⏭️" : "❌"
			printf "| %s | %s %s |\n", $1, mark, $3
		}'
	} >>"$GITHUB_STEP_SUMMARY"
fi

if [ -n "$failed" ]; then
	printf '%s\n' "$failed" | while IFS="$(printf '\t')" read -r name _ conclusion; do
		echo "::error title=Required job did not pass::$name ended as $conclusion"
	done
	exit 1
fi
echo "every required job passed"
