#!/usr/bin/env bats

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "release::prepare: preparation -> writes real files under a path containing spaces" {
    run release::prepare v1.2.3 production "$BUNDLE_DIR"
    assert_success
    assert_output "$BUNDLE_DIR"
    assert_release_bundle "$BUNDLE_DIR" 1.2.3 production
    refute_dir_empty "$BUNDLE_DIR"
    refute_file_empty "$BUNDLE_DIR/manifest.json"
    assert_file_readable "$BUNDLE_DIR/manifest.json"
    assert_file_writable "$BUNDLE_DIR/manifest.json"
    refute_file_executable "$BUNDLE_DIR/manifest.json"
    assert_file_contains --regexp "$BUNDLE_DIR/plan.txt" '^replicas: 3$'
    refute_file_contains "$BUNDLE_DIR/plan.txt" preview
}

@test "release::prepare: existing destination -> preserves the user's files" {
    mkdir "$BUNDLE_DIR"
    printf 'keep\n' > "$BUNDLE_DIR/important.txt"
    run release::prepare v1.2.3 production "$BUNDLE_DIR"
    assert_failure 73
    assert_output --partial 'destination already exists:'
    assert_file_contains "$BUNDLE_DIR/important.txt" keep
    refute_file_exists "$BUNDLE_DIR/manifest.json"
}

@test "release::prepare: invalid inputs -> creates no output directory" {
    run release::prepare wrong production "$BUNDLE_DIR"
    assert_failure 64
    refute_exists "$BUNDLE_DIR"
}

@test "release::prepare: encoder failure -> propagates the status without creating files" {
    mock jq '*' 'return 5'
    run release::prepare v1.2.3 production "$BUNDLE_DIR"
    assert_failure 5
    refute_exists "$BUNDLE_DIR"
    assert_called_times jq 1
}

@test "release::prepare: repeatable generation -> manifests and plans have identical contents" {
    prepare_bundle
    local other="$BATS_TEST_TMPDIR/second bundle"
    release::prepare v1.2.3 production "$other" >/dev/null
    assert_files_equal "$BUNDLE_DIR/manifest.json" "$other/manifest.json"
    assert_files_equal "$BUNDLE_DIR/plan.txt" "$other/plan.txt"
}

@test "release::prepare: environment changes -> generates a different manifest" {
    prepare_bundle production
    local other="$BATS_TEST_TMPDIR/staging bundle"
    release::prepare v1.2.3 staging "$other" >/dev/null
    refute_files_equal "$BUNDLE_DIR/manifest.json" "$other/manifest.json"
}

@test "assert_release_bundle: valid bundle -> the composed assertion passes" {
    prepare_bundle
    assert_passes assert_release_bundle "$BUNDLE_DIR" 1.2.3 production
}

@test "assert_release_bundle: wrong version -> the report names the JSON mismatch" {
    prepare_bundle
    assert_fails --partial 'JSON value differs' \
        assert_release_bundle "$BUNDLE_DIR" 9.9.9 production
}

@test "assert_release_bundle: missing manifest -> fails instead of silently accepting it" {
    mkdir "$BUNDLE_DIR"
    assert_fails assert_release_bundle "$BUNDLE_DIR" 1.2.3 production
}

@test "release::prepare: publication -> exposes a complete bundle with private permissions" {
    mock_spy mv
    local previous_umask current_umask
    previous_umask=$(umask)
    release::prepare v1.2.3 production "${BUNDLE_DIR}" >/dev/null
    current_umask=$(umask)
    assert_equal "${current_umask}" "${previous_umask}"
    assert_file_permission 700 "${BUNDLE_DIR}"
    assert_file_permission 600 "${BUNDLE_DIR}/plan.txt"
    assert_release_bundle "${BUNDLE_DIR}" 1.2.3 production
    assert_called_times mv 1
    assert_called_with mv "-T -n -- * ${BUNDLE_DIR}"
    run find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name '.releasectl.*'
    assert_success
    assert_output ''
}

@test "release::prepare: existing symlink -> preserves the link and its destination" {
    local original="${BATS_TEST_TMPDIR}/original"
    mkdir "${original}"
    printf keep > "${original}/marker"
    ln -s "${original}" "${BUNDLE_DIR}"
    run release::prepare v1.2.3 production "${BUNDLE_DIR}"
    assert_failure 73
    assert_link_exists "${BUNDLE_DIR}"
    assert_file_contains "${original}/marker" keep
    refute_file_exists "${original}/manifest.json"
}

@test "release::prepare: dangling symlink -> refuses to replace it" {
    ln -s "${BATS_TEST_TMPDIR}/absent" "${BUNDLE_DIR}"
    run release::prepare v1.2.3 production "${BUNDLE_DIR}"
    assert_failure 73
    assert_link_exists "${BUNDLE_DIR}"
    refute_dir_exists "${BATS_TEST_TMPDIR}/absent"
}

@test "release::prepare: missing destination -> refuses before writing files" {
    run release::prepare v1.2.3 production ''
    assert_failure 64
    assert_output 'missing destination'
    refute_dir_exists "${BUNDLE_DIR}"
}

@test "release::prepare: missing parent -> propagates the filesystem error" {
    run release::prepare v1.2.3 production "${BATS_TEST_TMPDIR}/absent/bundle"
    assert_failure
    refute_dir_exists "${BATS_TEST_TMPDIR}/absent"
}

@test "release::prepare: failed rename -> removes staging and leaves no partial bundle" {
    mock mv '*' 'return 74'
    run release::prepare v1.2.3 production "${BUNDLE_DIR}"
    assert_failure 74
    refute_dir_exists "${BUNDLE_DIR}"
    run find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name '.releasectl.*'
    assert_success
    assert_output ''
}

@test "release::prepare: destination appears before rename -> preserves the competing writer" {
    # shellcheck disable=SC2016  # create the competing bundle at the publication boundary
    mock mv '*' 'mkdir -- "$BUNDLE_DIR" || return; printf keep > "$BUNDLE_DIR/marker"; command mv "$@"'
    run release::prepare v1.2.3 production "${BUNDLE_DIR}"
    assert_failure 73
    assert_file_contains "${BUNDLE_DIR}/marker" keep
    refute_file_exists "${BUNDLE_DIR}/manifest.json"
    run find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name '.releasectl.*'
    assert_success
    assert_output ''
}

@test "release::prepare: concurrent writers -> publishes exactly one internally consistent bundle" {
    prepare_both() {
        local first second
        (
            result=0
            release::prepare v1.2.3 production "${BUNDLE_DIR}" >/dev/null 2>&1 || result=$?
            printf '%s\n' "${result}" > "${BATS_TEST_TMPDIR}/first.status"
        ) &
        first=$!
        (
            result=0
            release::prepare v2.0.0 staging "${BUNDLE_DIR}" >/dev/null 2>&1 || result=$?
            printf '%s\n' "${result}" > "${BATS_TEST_TMPDIR}/second.status"
        ) &
        second=$!
        wait "${first}" || return
        wait "${second}"
    }
    run prepare_both
    assert_success
    run sort "${BATS_TEST_TMPDIR}/first.status" "${BATS_TEST_TMPDIR}/second.status"
    assert_success
    assert_output $'0\n73'
    local version environment
    version=$(jq -r .version "${BUNDLE_DIR}/manifest.json")
    environment=$(jq -r .environment "${BUNDLE_DIR}/manifest.json")
    assert_one_of "${version}" 1.2.3 2.0.0
    assert_release_bundle "${BUNDLE_DIR}" "${version}" "${environment}"
    release::verify "${BUNDLE_DIR}/manifest.json"
    run find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name '.releasectl.*'
    assert_success
    assert_output ''
}
