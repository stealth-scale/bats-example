#!/usr/bin/env bats

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "release::validate_version: accepted tags -> succeeds without output" {
    run_matrix release::validate_version <<'CASES'
        # version        | status | output
        v0.0.0           | 0      | EMPTY
        v1.2.3           | 0      | EMPTY
        v10.20.30        | 0      | EMPTY
        v1.2.3-rc.1      | 0      | EMPTY
        v1.2.3-rc.12     | 0      | EMPTY
CASES
    refute_called curl
}

@test "release::validate_version: invalid tags -> explains the input error" {
    run_matrix release::validate_version <<'CASES'
        # An empty first field is an empty argument, not a missing row.
                         | 64 | invalid version:
        1.2.3            | 64 | invalid version: 1.2.3
        v01.2.3          | 64 | invalid version: v01.2.3
        v1.2             | 64 | invalid version: v1.2
        v1.2.3-rc.0      | 64 | invalid version: v1.2.3-rc.0
        v1.2.3 beta      | 64 | invalid version: v1.2.3 beta
        $(false)         | 64 | invalid version: $(false)
CASES
    # The matrix passed; status/output still describe its final command (exit 64).
    assert_failure 64
    refute_called curl
}

@test "release::validate_environment: accepted and rejected names -> keeps spelling explicit" {
    run_matrix release::validate_environment <<'CASES'
        staging     | 0  | EMPTY
        production  | 0  | EMPTY
        prod        | 64 | invalid environment: prod
        Production  | 64 | invalid environment: Production
                    | 64 | invalid environment:
CASES
}

@test "release::plan: versions and environments -> expected output fragments" {
    run_matrix release::plan <<'CASES'
        v1.2.3       | staging    | 0 | targets: preview
        v1.2.3       | production | 0 | targets: eu-west us-east
        v2.0.0-rc.1  | staging    | 0 | release: 2.0.0-rc.1
        invalid      | production | 64 | invalid version:
        v1.2.3       | unknown    | 64 | invalid environment:
CASES
}

@test "release::plan: multiline expectations -> preserves adjacent lines" {
    run_matrix release::plan <<'CASES'
        v1.2.3 | staging    | 0 | environment: staging\nreplicas: 1
        v1.2.3 | production | 0 | environment: production\nreplicas: 3
CASES
}

@test "release::plan: custom delimiter -> permits regex alternation" {
    run_matrix release::plan ';' <<'CASES'
        v1.2.3 ; staging    ; 0 ; ~ environment: (staging|production)
        v1.2.3 ; production ; 0 ; ~ targets: (preview|eu-west us-east)$
CASES
}

@test "release::plan: shared delimiter -> configures a semicolon-separated table" {
    # shellcheck disable=SC2034  # read by the matrix helper
    BATS_MATRIX_DELIMITER=';'
    run_matrix release::plan <<'CASES'
        v1.2.3 ; staging ; 0 ; release: 1.2.3
CASES
}

@test "release::plan: direct run -> separates useful output from diagnostics" {
    run --separate-stderr release::plan v1.2.3 production
    assert_success
    assert_stderr ''
    assert_line --index 0 'release: 1.2.3'
    assert_line --index 2 'replicas: 3'
    refute_line --partial preview
    assert_line_count "$output" 4
    assert_starts_with "$output" 'release: '
    assert_ends_with "$output" 'targets: eu-west us-east'
}

@test "release::plan: invalid input -> writes only stderr and performs no upload" {
    run --separate-stderr release::plan bad production
    assert_failure 64
    assert_output ''
    assert_stderr 'invalid version: bad'
    assert_stderr_line --index 0 'invalid version: bad'
    refute_stderr --partial 'unbound variable'
    refute_called curl
    refute_called sleep
}

@test "release::validate_endpoint: supported URLs -> accepts hosts, ports and base paths" {
    run_matrix release::validate_endpoint <<'CASES'
        https://api.example.invalid          | 0 | EMPTY
        https://api.example.invalid/         | 0 | EMPTY
        https://api.example.invalid:8443/v1  | 0 | EMPTY
        https://localhost:1                 | 0 | EMPTY
        https://127.0.0.1:65535              | 0 | EMPTY
CASES
}

@test "release::validate_endpoint: unsupported URLs -> refuses ambiguous or unsafe inputs" {
    run_matrix release::validate_endpoint <<'CASES'
                                               | 64 | invalid HTTPS endpoint:
        http://api.example.invalid             | 64 | invalid HTTPS endpoint:
        https://user:password@example.invalid   | 64 | invalid HTTPS endpoint:
        https://api.example.invalid?x=1         | 64 | invalid HTTPS endpoint:
        https://api.example.invalid/#fragment   | 64 | invalid HTTPS endpoint:
        https://api.example.invalid:0           | 64 | invalid HTTPS endpoint:
        https://api.example.invalid:65536       | 64 | invalid HTTPS endpoint:
        https://api.example.invalid:100000      | 64 | invalid HTTPS endpoint:
        https://api.example.invalid:abc         | 64 | invalid HTTPS endpoint:
        https://-api.example.invalid            | 64 | invalid HTTPS endpoint:
        https://api..example.invalid            | 64 | invalid HTTPS endpoint:
        https://api.example.invalid/a%0ab       | 64 | invalid HTTPS endpoint:
CASES
}
