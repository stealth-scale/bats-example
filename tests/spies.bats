#!/usr/bin/env bats

# shellcheck disable=SC2034
# The assertions read arrays by name.

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "mock_spy: nameref function -> records the call and preserves array changes" {
    local -a selected=()
    mock_spy release::targets
    release::targets selected production
    assert_array_equal selected eu-west us-east
    assert_called_with_args release::targets selected production
    assert_called_times release::targets 1
}

@test "mock_spy: run subshell -> records calls without leaking variable changes" {
    local -a selected=(untouched)
    mock_spy release::targets
    run release::targets selected production
    assert_success
    assert_array_equal selected untouched
    assert_called_once_with release::targets 'selected production'
}

@test "mock_spy: external jq -> runs the real JSON encoder" {
    mock_spy jq
    run release::manifest v1.2.3 production
    assert_success
    assert_called_times jq 1
    assert_args_contain jq '--arg version 1.2.3'
    # Assertions also invoke jq; finish checking its call count before using them.
    assert_json_equal "$output" .version 1.2.3
    assert_json_equal "$output" .targets '["eu-west","us-east"]'
}

@test "mock_spy: unmock -> restores the original function" {
    mock_spy release::targets
    local -a selected=()
    release::targets selected staging
    assert_called_times release::targets 1
    unmock release::targets
    release::targets selected production
    assert_array_equal selected eu-west us-east
    # Command-specific assertions require a live registration, even negative ones.
    assert_fails --partial 'Unregistered Mock' refute_called release::targets
}

@test "mock_spy: finite pipeline -> forwards output and records stdin" {
    mock_spy head
    # A wrapper keeps the pipeline inside run rather than piping Bats' own output.
    # shellcheck disable=SC2312  # common_setup enables pipefail for the whole pipeline
    preview_plan() { release::plan v1.2.3 production | head -n 1; }
    run preview_plan
    assert_success
    assert_output 'release: 1.2.3'
    assert_called_once_with head '-n 1'
    assert_stdin_equals head $'release: 1.2.3\nenvironment: production\nreplicas: 3\ntargets: eu-west us-east\n'
    assert_stdin_complete head 0
}

@test "mock_spy: original failure -> keeps its status and diagnostic" {
    mock_spy release::validate_environment
    run release::plan v1.2.3 unknown
    assert_failure 64
    assert_output 'invalid environment: unknown'
    assert_called_once_with release::validate_environment unknown
}
