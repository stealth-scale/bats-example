#!/usr/bin/env bats

bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }

@test "release::publish: successful upload -> sends exact argv and the complete manifest" {
    prepare_bundle
    mock -stdin curl "* $API_URL/releases" 'cat >/dev/null; printf "accepted\n"'
    run release::publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_success
    assert_output accepted
    assert_called_times curl 1
    assert_called_with_args curl --disable --fail --silent --show-error --connect-timeout 2 \
        --max-time 5 --request POST --header 'Content-Type: application/json' \
        --header 'Idempotency-Key: production/1.2.3' \
        --data-binary @- "$API_URL/releases"
    refute_called_with_args curl --header Content-Type: application/json
    assert_stdin_equals curl "$(< "$BUNDLE_DIR/manifest.json")"$'\n'
    assert_stdin_complete curl 0
    refute_called sleep
}

@test "release::publish: transient failure -> retries with the entire body and in order" {
    prepare_bundle
    mock_sequence -stdin curl '*' \
        'cat >/dev/null; return 7' \
        'cat >/dev/null; printf "accepted\n"'
    run release::publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_success
    assert_output accepted
    assert_called_times curl 2
    assert_called_once_with sleep 1
    assert_call_sequence curl 'sleep 1' curl
    local payload
    payload="$(< "$BUNDLE_DIR/manifest.json")"$'\n'
    assert_stdin_at_index curl 0 "$payload"
    assert_stdin_at_index curl 1 "$payload"
    assert_stdin_complete curl 0
    assert_stdin_complete curl 1
    assert_called_at_index_with_args curl 1 --disable --fail --silent --show-error --connect-timeout 2 \
        --max-time 5 --request POST --header 'Content-Type: application/json' \
        --header 'Idempotency-Key: production/1.2.3' \
        --data-binary @- "$API_URL/releases"
}

@test "release::publish: exhausted transport retries -> repeats the final response then stops" {
    prepare_bundle
    mock_sequence curl '*' 'cat >/dev/null; return 7' 'cat >/dev/null; return 28'
    run release::publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_failure 28
    assert_called_times curl 3
    assert_called_times sleep 2
    assert_call_sequence curl sleep curl sleep curl
    assert_called_at_index curl 2 "* $API_URL/releases"
}

@test "release::publish: staging policy -> limits retries to two attempts" {
    prepare_bundle staging
    mock curl '*' 'cat >/dev/null; return 28'
    run release::publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_failure 28
    assert_called_times curl 2
    assert_called_times sleep 1
}

@test "release::publish: table-driven retry policies -> all three helpers work together" {
    prepare_bundle production
    local staging="$BATS_TEST_TMPDIR/staging bundle"
    release::prepare v1.2.3 staging "$staging" >/dev/null
    mock -stdin curl '*' 'cat >/dev/null; return 7'

    # These are trusted test paths. An unquoted delimiter allows their expansion.
    run_matrix release::publish <<CASES
        $staging/manifest.json    | $API_URL | 7 | EMPTY
        $BUNDLE_DIR/manifest.json | $API_URL | 7 | EMPTY
CASES

    # Each row gets a run subshell, but the shared mock history survives both.
    assert_called_times curl 5
    assert_called_times sleep 3
    assert_call_sequence curl sleep curl curl sleep curl sleep curl
    assert_stdin_at_index curl 1 "$(< "$staging/manifest.json")"$'\n'
    assert_stdin_at_index curl 2 "$(< "$BUNDLE_DIR/manifest.json")"$'\n'
    assert_stdin_complete curl 4
    assert_json_equal --file "$staging/manifest.json" .environment staging
    assert_json_equal --file "$BUNDLE_DIR/manifest.json" .environment production
}

@test "release::publish: interrupted backoff -> stops before another upload" {
    prepare_bundle
    mock curl '*' 'cat >/dev/null; return 7'
    mock sleep '*' 'return 42'
    run release::publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_failure 42
    assert_called_times curl 1
    assert_called_once_with sleep 1
}

@test "release::publish: parallel uploads -> keeps both complete request histories" {
    prepare_bundle production
    local staging="$BATS_TEST_TMPDIR/staging bundle"
    release::prepare v1.2.3 staging "$staging" >/dev/null
    mock -stdin curl '*' 'cat >/dev/null; printf "accepted\n"'
    publish_both() {
        local first second result=0
        release::publish "$BUNDLE_DIR/manifest.json" "$API_URL" >/dev/null &
        first=$!
        release::publish "$staging/manifest.json" "$API_URL" >/dev/null &
        second=$!
        wait "$first" || result=$?
        wait "$second" || result=$?
        return "$result"
    }
    run publish_both
    assert_success
    assert_output ''
    assert_called_times curl 2
    assert_stdin_equals curl "$(< "$BUNDLE_DIR/manifest.json")"$'\n'
    assert_stdin_equals curl "$(< "$staging/manifest.json")"$'\n'
    assert_stdin_complete curl 0
    assert_stdin_complete curl 1
    refute_called sleep
}

@test "release::publish: argument rules -> production overrides a default response" {
    prepare_bundle
    mock curl '*' 'cat >/dev/null; printf "default\n"'
    mock curl '~https://prod[.]example[.]invalid/releases$' 'cat >/dev/null; printf "production\n"'
    run release::publish "$BUNDLE_DIR/manifest.json" https://prod.example.invalid
    assert_success
    assert_output production
    assert_called_with curl '~--request POST.*prod[.]example[.]invalid/releases$'
    assert_args_contain curl 'Content-Type: application/json'
    refute_called_with curl '* --request DELETE *'
}

@test "release::publish: trailing slash -> does not duplicate the URL separator" {
    prepare_bundle
    mock curl "* $API_URL/releases" 'cat >/dev/null'
    run release::publish "$BUNDLE_DIR/manifest.json" "$API_URL/"
    assert_success
    assert_called_once_with curl "* $API_URL/releases"
    refute_called_with curl '*//releases'
}

@test "release::publish: insecure endpoint -> rejects before calling curl" {
    prepare_bundle
    run release::publish "$BUNDLE_DIR/manifest.json" http://api.example.invalid
    assert_failure 64
    assert_output --partial 'invalid HTTPS endpoint:'
    refute_called curl
    refute_called sleep
}

@test "release::publish: missing file -> reports the error without an upload" {
    run release::publish "$BUNDLE_DIR/missing.json" "$API_URL"
    assert_failure 64
    assert_output --partial 'manifest not found:'
    refute_called curl
}

@test "release::publish: malformed JSON -> cannot reach the network" {
    local manifest="$BATS_TEST_TMPDIR/broken.json"
    printf '{broken\n' > "$manifest"
    refute_json_valid --file "$manifest"
    run release::publish "$manifest" "$API_URL"
    assert_failure 64
    assert_output --partial 'invalid manifest'
    refute_called curl
}

@test "release::publish: valid JSON with the wrong schema -> cannot reach the network" {
    local manifest="$BATS_TEST_TMPDIR/incomplete.json"
    printf '{"version":"1.2.3"}\n' > "$manifest"
    assert_json_valid --file "$manifest"
    run release::publish "$manifest" "$API_URL"
    assert_failure 64
    refute_called curl
}

@test "release::publish: invalid manifest version -> validates before upload" {
    prepare_bundle
    local invalid="$BATS_TEST_TMPDIR/invalid-version.json"
    jq '.version = "not-a-version"' "$BUNDLE_DIR/manifest.json" > "$invalid"
    run release::publish "$invalid" "$API_URL"
    assert_failure 64
    assert_output --partial 'invalid version:'
    refute_called curl
}

@test "release::publish: unexpected mock arguments -> strict matching reports a mistake" {
    prepare_bundle
    unmock curl
    mock curl '* --request DELETE *' 'cat >/dev/null'
    run -127 release::publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_failure 127
    assert_output --partial 'unexpected args'
    assert_called_times curl 1
    refute_called sleep
}

@test "release::publish: debug -> rules and call history remain available after run" {
    prepare_bundle
    mock curl '*' 'cat >/dev/null; printf "accepted\n"'
    run release::publish "$BUNDLE_DIR/manifest.json" "$API_URL"
    assert_success
    run mock_debug 1
    assert_success
    assert_output --partial curl
    assert_output --partial "$API_URL/releases"
}

@test "release::publish::retryable: transport errors -> explicitly classifies retry policy" {
    run_matrix release::publish::retryable <<'CASES'
        6   | 0 | EMPTY
        7   | 0 | EMPTY
        18  | 0 | EMPTY
        28  | 0 | EMPTY
        52  | 0 | EMPTY
        55  | 0 | EMPTY
        56  | 0 | EMPTY
        0   | 1 | EMPTY
        22  | 1 | EMPTY
        23  | 1 | EMPTY
        35  | 1 | EMPTY
        60  | 1 | EMPTY
        127 | 1 | EMPTY
CASES
}

@test "release::publish: HTTP and TLS failures -> stop without exhausting the retry budget" {
    prepare_bundle
    mock_sequence curl '*' 'cat >/dev/null; return 22' 'cat >/dev/null; return 60'
    run release::publish "${BUNDLE_DIR}/manifest.json" "${API_URL}"
    assert_failure 22
    assert_called_times curl 1
    refute_called sleep
    run release::publish "${BUNDLE_DIR}/manifest.json" "${API_URL}"
    assert_failure 60
    assert_called_times curl 2
    refute_called sleep
    assert_dir_empty "${TMPDIR}"
}

@test "release::publish: source changes during retries -> resends the original snapshot" {
    prepare_bundle
    local payload
    payload="$(< "${BUNDLE_DIR}/manifest.json")"$'\n'
    # shellcheck disable=SC2016  # the action mutates the source after the first upload
    mock_sequence -stdin curl '*' \
        'cat >/dev/null; printf broken > "$BUNDLE_DIR/manifest.json"; return 7' \
        'cat >/dev/null; printf accepted'
    run release::publish "${BUNDLE_DIR}/manifest.json" "${API_URL}"
    assert_success
    assert_output accepted
    assert_stdin_at_index curl 0 "${payload}"
    assert_stdin_at_index curl 1 "${payload}"
    refute_json_valid --file "${BUNDLE_DIR}/manifest.json"
    assert_dir_empty "${TMPDIR}"
}

@test "release::publish: failed response body -> does not mix partial data with the successful response" {
    prepare_bundle
    mock_sequence curl '*' 'cat >/dev/null; printf partial; return 7' 'cat >/dev/null; printf accepted'
    run release::publish "${BUNDLE_DIR}/manifest.json" "${API_URL}"
    assert_success
    assert_output accepted
    assert_dir_empty "${TMPDIR}"
}

@test "release::publish: exhausted retries -> cleans private payload and response files" {
    prepare_bundle
    mock curl '*' 'cat >/dev/null; printf incomplete; return 28'
    run release::publish "${BUNDLE_DIR}/manifest.json" "${API_URL}"
    assert_failure 28
    assert_output ''
    assert_called_times curl 3
    assert_dir_empty "${TMPDIR}"
}

@test "release::publish: snapshot copy fails -> cleans scratch space before returning the I/O error" {
    prepare_bundle
    mock cp '*' 'return 74'
    run release::publish "${BUNDLE_DIR}/manifest.json" "${API_URL}"
    assert_failure 74
    refute_called curl
    refute_called sleep
    assert_dir_empty "${TMPDIR}"
}

@test "release::publish: invalid policy -> performs no upload and removes its snapshot" {
    prepare_bundle
    local invalid="${BATS_TEST_TMPDIR}/invalid.json"
    jq '.replicas = 1000' "${BUNDLE_DIR}/manifest.json" > "${invalid}"
    run release::publish "${invalid}" "${API_URL}"
    assert_failure 64
    refute_called curl
    refute_called sleep
    assert_dir_empty "${TMPDIR}"
}

@test "release::publish: TERM during upload -> exits promptly and removes the private snapshot" {
    prepare_bundle
    # shellcheck disable=SC2016  # signal only the application subshell running the action
    mock curl '*' 'cat >/dev/null; kill -TERM "$BASHPID"'
    run timeout --kill-after=1 10 "${EXAMPLE_ROOT}/bin/releasectl" publish "${BUNDLE_DIR}/manifest.json" "${API_URL}"
    assert_failure 143
    assert_called_times curl 1
    refute_called sleep
    assert_dir_empty "${TMPDIR}"
}
