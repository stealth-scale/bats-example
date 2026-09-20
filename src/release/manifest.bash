# module: release/manifest
# Schema 1 is a closed contract: generated policy and accepted input must agree.

#######################################
# Encodes a manifest with jq; shell strings are never interpolated into JSON code.
# Usage: release::manifest v1.2.3 production
# Arguments: $1 - Version tag; $2 - Environment.
# Outputs: One JSON object to stdout, followed by a newline.
# Returns: 0 on success; 64 for invalid input; jq's status on encoder failure.
#######################################
release::manifest() {
    release::internal::arity "$#" 2 2 'release::manifest VERSION ENVIRONMENT' || return
    local version
    local -a targets=()
    local -A settings=()
    release::version version "${1}" || return
    release::targets targets "${2}" || return
    release::settings settings "${2}" || return
    jq -n --arg version "${version}" --arg environment "${2}" \
        --argjson replicas "${settings[replicas]}" --args \
        '{schema: 1, version: $version, environment: $environment,
          replicas: $replicas, targets: $ARGS.positional}' "${targets[@]}"
}

#######################################
# Validates exactly one JSON object against the application's versioned contract.
# Compares decoded JSON, not formatting; rejects unknown keys and inconsistent policy.
# Usage: release::verify /tmp/bundle/manifest.json
# Arguments: $1 - Readable regular manifest file.
# Outputs: Nothing on success; a diagnostic on stderr otherwise.
# Returns: 0 when valid; 64 for missing/invalid input; a tool failure otherwise.
#######################################
release::verify() {
    release::internal::arity "$#" 1 1 'release::verify MANIFEST' || return
    if [[ ! -f "${1}" || ! -r "${1}" ]]; then
        release::internal::error 64 "manifest not found: ${1}"
        return 64
    fi
    local document version environment expected
    document=$(jq -ces '
        if length == 1 and (.[0] | type == "object")
            and (.[0].version | type == "string")
            and (.[0].environment | type == "string")
        then .[0] else error("invalid manifest") end
    ' -- "${1}" 2>/dev/null) || {
        release::internal::error 64 'invalid manifest'
        return 64
    }
    version=$(jq -r .version <<< "${document}") || return
    environment=$(jq -r .environment <<< "${document}") || return
    release::validate_version "v${version}" || return
    expected=$(release::manifest "v${version}" "${environment}") || return
    if ! jq -en --argjson actual "${document}" --argjson expected "${expected}" \
        '$actual == $expected' >/dev/null; then
        release::internal::error 64 'invalid manifest: schema or deployment policy differs'
        return 64
    fi
}
