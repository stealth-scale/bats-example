#!/usr/bin/env bash
# Run the supplied Bats command and verify each intentional failure's diagnostic.
# Used separately from the passing suite so a setup error cannot count as success.
set -euo pipefail

if (( $# == 0 )); then
    printf 'Usage: check-reports.bash COMMAND [ARGUMENTS...]\n' >&2
    exit 2
fi

report=$(mktemp)
trap 'rm -f -- "$report"' EXIT
result=0
"$@" >"$report" 2>&1 || result=$?
cat "$report"

if (( result != 1 )); then
    printf 'Expected Bats status 1 for the failure demos, got %s\n' "$result" >&2
    exit 1
fi

# Check each TAP record separately; a failure elsewhere cannot supply its message.
awk '
    /^1\.\.3$/ { plan = 1 }
    /^not ok [0-9]+ / {
        count++
        current = count
        if (count == 1 && $0 !~ /demo: expect ->/) bad = 1
        if (count == 2 && $0 !~ /demo: matrix ->/) bad = 1
        if (count == 3 && $0 !~ /demo: mock ->/) bad = 1
        next
    }
    /^ok [0-9]+ / { bad = 1; current = 0 }
    /^Bail out!/ { bad = 1 }
    /^#/ && current == 1 && /JSON value differs/ { expect = 1 }
    /^#/ && current == 2 && /MATRIX TEST FAILED/ { matrix = 1 }
    /^#/ && current == 3 && /Argument Mismatch/ { mock = 1 }
    END { exit !(plan && count == 3 && expect && matrix && mock && !bad) }
' "$report" || {
    printf 'The failure demos did not produce the three expected assertion reports.\n' >&2
    exit 1
}
printf '\nAll three failure reports verified.\n'
