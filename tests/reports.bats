#!/usr/bin/env bats
# Negative tests for the diagnostic checker; make test-reports runs the real demos.
bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "check-reports: passing command -> rejects an unexpectedly green demonstration" {
    run bash "${EXAMPLE_ROOT}/scripts/check-reports.bash" true
    assert_failure 1
    assert_output --partial 'Expected Bats status 1'
}

@test "check-reports: tool error -> does not mistake an infrastructure failure for an assertion" {
    run bash "${EXAMPLE_ROOT}/scripts/check-reports.bash" bash -c 'exit 2'
    assert_failure 1
    assert_output --partial 'got 2'
}

@test "check-reports: setup failures -> requires the actual assertion diagnostics" {
    # shellcheck disable=SC2016  # evaluated by the child Bash
    run bash "${EXAMPLE_ROOT}/scripts/check-reports.bash" bash -c '
        printf "%s\n" "1..3" \
            "not ok 1 demo: expect -> setup failed" \
            "not ok 2 demo: matrix -> setup failed" \
            "not ok 3 demo: mock -> setup failed"
        exit 1
    '
    assert_failure 1
    assert_output --partial 'did not produce the three expected assertion reports'
}

@test "check-reports: absent command -> reports its usage" {
    run bash "${EXAMPLE_ROOT}/scripts/check-reports.bash"
    assert_failure 2
    assert_output --partial 'Usage:'
}
