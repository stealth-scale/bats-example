# module: release/publish
# Bounded transport retries against a private, validated snapshot of the payload.

#######################################
# Classifies transient transport failures; HTTP, TLS and local errors fail closed.
# Usage: release::publish::retryable 7
# Arguments: $1 - curl exit status.
# Returns: 0 for DNS/connect/partial-transfer/timeout/send/receive failures; 1 otherwise.
#######################################
release::publish::retryable() {
    case "${1:-}" in
        6|7|18|28|52|55|56) return 0 ;;
        *) return 1 ;;
    esac
}

#######################################
# Uploads one immutable snapshot; only a successful response reaches stdout.
# Disables curlrc loading. TLS verification stays enabled, and redirects are not followed.
# Retries reopen the same bytes and reuse the same idempotency key. The server must
# honor that key; client retries alone cannot guarantee exactly-once processing.
# Usage: release::publish /tmp/bundle/manifest.json https://api.example.invalid
# Arguments: $1 - Manifest file; $2 - HTTPS endpoint without /releases.
# Globals: TMPDIR (Read, defaults to /tmp).
# Outputs: Successful response to stdout; tool/validation errors to stderr.
# Returns: 0 on success; 64 for invalid input; curl, sleep or I/O status on failure.
#######################################
release::publish() (
    release::internal::arity "$#" 2 2 'release::publish MANIFEST HTTPS_ENDPOINT' || return
    local manifest="${1}" endpoint="${2}"
    if [[ ! -f "${manifest}" || ! -r "${manifest}" ]]; then
        release::internal::error 64 "manifest not found: ${manifest}"
        return 64
    fi
    release::validate_endpoint "${endpoint}" || return
    local scratch environment version attempt result=0
    umask 077
    scratch=$(mktemp -d -- "${TMPDIR:-/tmp}/releasectl.XXXXXXXX") || return
    trap 'rm -rf -- "${scratch}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    cp -- "${manifest}" "${scratch}/manifest.json" || return
    manifest="${scratch}/manifest.json"
    release::verify "${manifest}" || return
    environment=$(jq -r .environment -- "${manifest}") || return
    version=$(jq -r .version -- "${manifest}") || return
    local -A settings=()
    release::settings settings "${environment}" || return
    for ((attempt=1; attempt<=settings[attempts]; attempt++)); do
        if curl --disable --fail --silent --show-error --connect-timeout 2 --max-time 5 \
            --request POST --header 'Content-Type: application/json' \
            --header "Idempotency-Key: ${environment}/${version}" \
            --data-binary @- "${endpoint%/}/releases" < "${manifest}" > "${scratch}/response"; then
            cat -- "${scratch}/response"
            return $?
        else
            result=$?
        fi
        release::publish::retryable "${result}" || return "${result}"
        if (( attempt < settings[attempts] )); then sleep 1 || return; fi
    done
    return "${result}"
)
