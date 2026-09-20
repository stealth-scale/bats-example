#!/usr/bin/env bash
# Loaded by name through BATS_LIB_PATH, just like the three helper libraries.
# Each suite explicitly calls common_setup and common_teardown in its Bats hooks.
bats_load_library bats-expect
bats_load_library bats-mock
bats_load_library bats-matrix

EXAMPLE_ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/../../.." && pwd -P)
# shellcheck source=src/load.bash
source "$EXAMPLE_ROOT/src/load.bash"

#######################################
# Starts an isolated mock session and replaces uploads and retry sleeps.
# Usage: setup() { common_setup; }
# Arguments: None
# Globals: BUNDLE_DIR, API_URL (Write); BATS_TEST_TMPDIR (Read)
# Returns: 0 when the test environment is ready; nonzero on setup failure.
#######################################
common_setup() {
    set -Euo pipefail
    bats_require_minimum_version 1.7.0
    export BATS_MOCK_STATE_DIR="$BATS_TEST_TMPDIR/mocks"
    export BATS_MOCK_GLOBAL_LOG="$BATS_MOCK_STATE_DIR/global.log"
    export BATS_MOCK_STRICT=1
    mock_setup

    # All application scratch files belong to this test, including failure paths.
    export TMPDIR="${BATS_TEST_TMPDIR}/scratch"
    mkdir -p -- "${TMPDIR}"

    # Fail closed: even an unexpected upload cannot reach a real service.
    mock curl '*' 'printf "unexpected network call\n" >&2; return 99'
    mock sleep '*' 'return 0'
    BUNDLE_DIR="$BATS_TEST_TMPDIR/release bundle"
    # shellcheck disable=SC2034  # used by the test files
    API_URL=https://api.example.invalid
}

#######################################
# Restores mocked functions and removes only this test's owned mock session.
# Usage: teardown() { common_teardown; }
# Arguments: None
# Returns: 0 on cleanup; nonzero if session ownership no longer matches.
#######################################
common_teardown() {
    mock_teardown
}

#######################################
# Writes a real release bundle; no filesystem operations are mocked.
# Usage: prepare_bundle [staging|production]
# Arguments: $1 - Optional environment, defaults to production.
# Globals: BUNDLE_DIR (Read)
# Returns: The status of release::prepare.
#######################################
prepare_bundle() {
    release::prepare v1.2.3 "${1:-production}" "$BUNDLE_DIR" >/dev/null
}

#######################################
# Composes bats-expect assertions into one application-level contract.
# Usage: assert_release_bundle DIRECTORY VERSION ENVIRONMENT
# Arguments: $1 - Bundle directory; $2 - Normalized version; $3 - Environment.
# Returns: 0 for a valid bundle; nonzero with the first assertion's diagnostic.
#######################################
assert_release_bundle() {
    local directory=$1 version=$2 environment=$3
    assert_dir_exists "$directory" || return
    assert_file_exists "$directory/manifest.json" || return
    assert_file_permission 600 "$directory/manifest.json" || return
    assert_json_valid --file "$directory/manifest.json" || return
    assert_json_equal --file "$directory/manifest.json" .version "$version" || return
    assert_json_equal --file "$directory/manifest.json" .environment "$environment" || return
    assert_file_contains "$directory/plan.txt" "release: $version"
}
