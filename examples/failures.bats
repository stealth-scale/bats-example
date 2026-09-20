#!/usr/bin/env bats
# Intentionally failing examples, excluded from the normal tests/ suite.
# Run: make test TARGET=examples/failures.bats

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "demo: expect -> shows the actual JSON value" {
    run release::manifest v1.2.3 production
    assert_success
    assert_json_equal "$output" .replicas 99
}

@test "demo: matrix -> identifies the failing row and command" {
    run_matrix release::plan <<'CASES'
        v1.2.3 | staging    | 0 | replicas: 1
        v1.2.3 | production | 0 | replicas: 99
CASES
}

@test "demo: mock -> shows the recorded arguments" {
    prepare_bundle
    mock curl '*' 'cat >/dev/null; printf "accepted\n"'
    run release::publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_success
    assert_called_with_args curl --request DELETE "$API_URL/releases"
}
