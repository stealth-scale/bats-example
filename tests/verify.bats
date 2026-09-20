#!/usr/bin/env bats

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "release::verify: generated manifests -> accepts every supported policy" {
    prepare_bundle production
    local staging="${BATS_TEST_TMPDIR}/staging"
    release::prepare v2.0.0-rc.1 staging "${staging}" >/dev/null
    run_matrix release::verify <<CASES
        ${BUNDLE_DIR}/manifest.json | 0 | EMPTY
        ${staging}/manifest.json    | 0 | EMPTY
CASES
    refute_called curl
}

@test "release::verify: JSON formatting -> ignores whitespace and object key order" {
    prepare_bundle
    local reordered="${BATS_TEST_TMPDIR}/reordered.json"
    jq -Sc . "${BUNDLE_DIR}/manifest.json" > "${reordered}"
    run release::verify "${reordered}"
    assert_success
    assert_output ''
}

@test "release::verify: invalid documents -> rejects empty, scalar, malformed and multiple JSON values" {
    local document="${BATS_TEST_TMPDIR}/document.json"
    verify_document() {
        printf '%s\n' "${1}" > "${document}"
        release::verify "${document}"
    }
    run_matrix verify_document <<'CASES'
                               | 64 | invalid manifest
        null                   | 64 | invalid manifest
        []                     | 64 | invalid manifest
        {}                     | 64 | invalid manifest
        {broken                | 64 | invalid manifest
        {"version": 123}       | 64 | invalid manifest
        {} {}                  | 64 | invalid manifest
CASES
    refute_called curl
}

@test "release::verify: contract mutations -> rejects schema, type and policy disagreements" {
    prepare_bundle
    local changed="${BATS_TEST_TMPDIR}/changed.json"
    verify_changed_field() {
        jq --arg key "${1}" --argjson value "${2}" '.[$key] = $value' \
            "${BUNDLE_DIR}/manifest.json" > "${changed}" || return
        release::verify "${changed}"
    }
    run_matrix verify_changed_field <<'CASES'
        schema      | 2                         | 64 | schema or deployment policy differs
        schema      | "1"                       | 64 | schema or deployment policy differs
        replicas    | 0                         | 64 | schema or deployment policy differs
        replicas    | 1                         | 64 | schema or deployment policy differs
        replicas    | 3.5                       | 64 | schema or deployment policy differs
        replicas    | "3"                       | 64 | schema or deployment policy differs
        targets     | []                        | 64 | schema or deployment policy differs
        targets     | ["eu-west", "eu-west"]    | 64 | schema or deployment policy differs
        targets     | ["us-east", "eu-west"]    | 64 | schema or deployment policy differs
        targets     | ["preview"]               | 64 | schema or deployment policy differs
        extra       | true                      | 64 | schema or deployment policy differs
        environment | "unknown"                 | 64 | invalid environment:
        version     | "not-a-version"           | 64 | invalid version:
CASES
    refute_called curl
}

@test "release::verify: trailing document -> rejects an otherwise valid first manifest" {
    prepare_bundle
    printf '\nnull\n' >> "${BUNDLE_DIR}/manifest.json"
    run release::verify "${BUNDLE_DIR}/manifest.json"
    assert_failure 64
    assert_output 'invalid manifest'
}

@test "release::verify: missing file or directory -> reports invalid input" {
    run_matrix release::verify <<CASES
        ${BATS_TEST_TMPDIR}/missing.json | 64 | manifest not found:
        ${BATS_TEST_TMPDIR}              | 64 | manifest not found:
CASES
}
