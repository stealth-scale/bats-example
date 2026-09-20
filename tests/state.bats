#!/usr/bin/env bats

# shellcheck disable=SC2034
# bats-expect reads variables and arrays by name, not by expansion at the call site.

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "release::version: nameref -> normalizes without losing the caller's value" {
    local normalized=''
    assert_var_set normalized
    assert_var_empty normalized
    release::version normalized v1.2.3
    assert_var_equal normalized 1.2.3
    refute_var_empty normalized
    refute_equal "$normalized" v1.2.3
}

@test "release::version: run_nameref -> uses ordinary output assertions" {
    run_nameref release::version v2.0.0-rc.1
    assert_success
    assert_output 2.0.0-rc.1
    assert_contains "$output" -rc.
    refute_contains "$output" staging
}

@test "release::version: nameref shortcuts -> preserve the test's run result" {
    run release::plan v1.2.3 staging
    assert_nameref 1.2.3 release::version v1.2.3
    refute_nameref v1.2.3 release::version v1.2.3
    assert_success
    assert_line --index 0 'release: 1.2.3'
}

@test "release::targets: indexed array -> production targets remain ordered" {
    local -a targets=()
    assert_array_empty targets
    release::targets targets production
    assert_declared -a targets
    assert_array_equal targets eu-west us-east
    assert_array_length targets 2
    assert_array_contains targets eu-west
    refute_array_contains targets preview
    refute_array_empty targets
    assert_array_has_key targets 1
    refute_array_has_key targets 2
}

@test "release::targets: invalid environment -> leaves the caller's array intact" {
    local -a targets=(keep)
    local result=0
    release::targets targets unknown 2>/dev/null || result=$?
    assert_equal "$result" 64
    assert_array_equal targets keep
}

@test "release::targets: run_nameref -> exposes an array as separate output lines" {
    run_nameref release::targets production
    assert_success
    assert_output $'eu-west\nus-east'
    assert_line --index 1 us-east
}

@test "release::settings: associative array -> contains only the environment policy" {
    local -A settings=()
    release::settings settings production
    assert_declared -A settings
    assert_array_length settings 2
    assert_array_has_key settings replicas
    assert_array_has_key settings attempts
    refute_array_has_key settings token
    assert_equal "${settings[replicas]}" 3
    assert_equal "${settings[attempts]}" 3
}

@test "release::settings: capacity -> production stays inside the deployment budget" {
    local -A settings=()
    local -a targets=()
    release::settings settings production
    release::targets targets production
    local instances=$((settings[replicas] * ${#targets[@]}))
    assert_is_int "$instances"
    assert_between "$instances" 1 10
    assert_gt "$instances" "${settings[replicas]}"
    assert_le "${settings[attempts]}" 3
    assert_is_identifier replicas
}
