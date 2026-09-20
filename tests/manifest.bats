#!/usr/bin/env bats

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "release::manifest: production -> emits the deployment contract as JSON" {
    run release::manifest v1.2.3 production
    assert_success
    assert_json_valid "$output"
    assert_json_equal "$output" .schema 1
    assert_json_equal "$output" .version 1.2.3
    assert_json_equal "$output" .replicas 3
    assert_json_equal "$output" .targets '["eu-west","us-east"]'
    assert_json_length "$output" .targets 2
    assert_json_has_key "$output" .environment
    refute_json_has_key "$output" .token
    refute_json_equal "$output" .environment staging
    refute_called curl
}

@test "release::manifest: staging -> uses preview without production capacity" {
    run release::manifest v1.2.3-rc.1 staging
    assert_success
    assert_json_equal "$output" .version 1.2.3-rc.1
    assert_json_equal "$output" .replicas 1
    assert_json_length "$output" .targets 1
    assert_json_equal "$output" '.targets[0]' preview
}
