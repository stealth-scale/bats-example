#!/usr/bin/env bats

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "host tools: GNU mv with platform stat -> reads real file permissions" {
    run mv --version
    assert_success
    assert_output --partial 'GNU coreutils'
    # bats-expect chooses stat's flags by OS. In particular, macOS must keep BSD stat.
    local probe="${BATS_TEST_TMPDIR}/permission probe"
    printf probe > "${probe}"
    chmod 640 "${probe}"
    assert_file_permission 640 "${probe}"
    chmod 600 "${probe}"
    assert_file_permission 600 "${probe}"
}

@test "release::internal::require_bash: version boundaries -> rejects unsupported runtimes" {
    run_matrix release::internal::require_bash <<'CASES'
        3 | 2 | 2 | requires Bash 4.4
        4 | 3 | 2 | requires Bash 4.4
        4 | 4 | 0 | EMPTY
        5 | 0 | 0 | EMPTY
CASES
}

@test "release API: missing or extra arguments -> returns usage without nounset failures" {
    local function_name
    for function_name in release::validate_version release::validate_environment release::validate_endpoint \
        release::version release::targets release::settings release::plan release::manifest \
        release::prepare release::verify release::publish; do
        run "${function_name}"
        assert_failure 64
        assert_output --partial 'usage:'
        refute_output --partial 'unbound variable'
        run "${function_name}" one two three four
        assert_failure 64
        assert_output --partial 'usage:'
    done
    refute_called curl
    refute_called sleep
}

@test "release namerefs: output names -> reject expressions and the internal namespace" {
    local name function_name
    # shellcheck disable=SC2016  # names are data and must never be evaluated
    for name in '' 'array[0]' '$(false)' _release_version_out; do
        for function_name in release::version release::targets release::settings; do
            run "${function_name}" "${name}" v1.2.3
            assert_failure 64
            assert_output --partial 'invalid output variable:'
        done
    done
}

@test "release library: repeated imports -> preserve options, traps, cwd and umask" {
    # shellcheck disable=SC2016  # inspected inside the fresh Bash process
    run bash -euo pipefail -c '
        trap : TERM
        before_options=$(set +o)
        before_traps=$(trap -p)
        before_umask=$(umask)
        before_directory=$PWD
        source "$1"
        source "$1"
        [[ $(set +o) == "$before_options" ]]
        [[ $(trap -p) == "$before_traps" ]]
        [[ $(umask) == "$before_umask" ]]
        [[ $PWD == "$before_directory" ]]
        declare -F release::main >/dev/null
    ' _ "${EXAMPLE_ROOT}/src/load.bash"
    assert_success
    assert_output ''
}
