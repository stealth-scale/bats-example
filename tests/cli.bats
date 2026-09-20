#!/usr/bin/env bats

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "release::main: help -> starts the actual executable and describes the commands" {
    run "$EXAMPLE_ROOT/bin/releasectl" --help
    assert_success
    assert_line --index 0 'Usage: releasectl COMMAND [ARGS]'
    assert_line '  publish MANIFEST HTTPS_ENDPOINT'
}

@test "release::main: default command -> prints help" {
    run "$EXAMPLE_ROOT/bin/releasectl"
    assert_success
    assert_output --partial 'Usage: releasectl'
}

@test "release::main: argument counts -> rejects missing and extra inputs" {
    run_matrix release::main <<'CASES'
        plan    | 64 | invalid command or arguments:
        prepare | 64 | invalid command or arguments:
        publish | 64 | invalid command or arguments:
        verify  | 64 | invalid command or arguments:
        destroy | 64 | invalid command or arguments:
CASES
    run "$EXAMPLE_ROOT/bin/releasectl" plan v1.2.3 staging extra
    assert_failure 64
}

@test "release::main: plan -> works in a fresh Bash process" {
    run "$EXAMPLE_ROOT/bin/releasectl" plan v1.2.3 production
    assert_success
    assert_output $'release: 1.2.3\nenvironment: production\nreplicas: 3\ntargets: eu-west us-east'
}

@test "release::main: manifest -> produces machine-readable output without stderr" {
    run --separate-stderr "$EXAMPLE_ROOT/bin/releasectl" manifest v1.2.3 staging
    assert_success
    assert_stderr ''
    assert_json_equal "$output" .environment staging
}

@test "release::main: prepare -> creates a bundle through the public entry point" {
    run "$EXAMPLE_ROOT/bin/releasectl" prepare v1.2.3 production "$BUNDLE_DIR"
    assert_success
    assert_release_bundle "$BUNDLE_DIR" 1.2.3 production
}

@test "release::main: publish -> exported command mock intercepts the child Bash process" {
    prepare_bundle
    mock curl '*' 'cat >/dev/null; printf "accepted\n"'
    run "$EXAMPLE_ROOT/bin/releasectl" publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_success
    assert_output accepted
    assert_called_times curl 1
    assert_stdin_complete curl 0
    refute_called sleep
}

@test "release::main: source -> importing the library is silent" {
    # shellcheck disable=SC2016  # expanded by the fresh child shell
    run bash -euo pipefail -c 'source "$1"; declare -F release::main >/dev/null' \
        _ "$EXAMPLE_ROOT/src/load.bash"
    assert_success
    assert_output ''
}

@test "release::main: verify -> accepts a prepared bundle through the executable" {
    prepare_bundle
    run --separate-stderr "${EXAMPLE_ROOT}/bin/releasectl" verify "${BUNDLE_DIR}/manifest.json"
    assert_success
    assert_output ''
    assert_stderr ''
    refute_called curl
}
