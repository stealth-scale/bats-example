# module: release/validation
# Input validation without filesystem or network operations.

#######################################
# Accepts vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rc.N, without leading zeros.
# Usage: release::validate_version v1.2.3
# Arguments: $1 - Version tag; the release-candidate number starts at 1.
# Returns: 0 when valid; 64 with a diagnostic otherwise.
#######################################
release::validate_version() {
    release::internal::arity "$#" 1 1 'release::validate_version VERSION' || return
    local pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc\.[1-9][0-9]*)?$'
    if [[ ! "${1}" =~ ${pattern} ]]; then
        release::internal::error 64 "invalid version: ${1}"
        return 64
    fi
}

#######################################
# Accepts the two environments for which this application defines a policy.
# Usage: release::validate_environment production
# Arguments: $1 - Environment name, case-sensitive.
# Returns: 0 for staging or production; 64 with a diagnostic otherwise.
#######################################
release::validate_environment() {
    release::internal::arity "$#" 1 1 'release::validate_environment ENVIRONMENT' || return
    case "${1}" in
        staging|production) return 0 ;;
        *) release::internal::error 64 "invalid environment: ${1}" ;;
    esac
}

#######################################
# Accepts an HTTPS DNS/IPv4 host, optional port and optional base path.
# Credentials, query strings, fragments, IPv6 and percent escapes are not supported.
# Usage: release::validate_endpoint https://api.example.invalid:8443/v1
# Arguments: $1 - Endpoint without /releases.
# Returns: 0 when valid; 64 with a diagnostic otherwise.
#######################################
release::validate_endpoint() {
    release::internal::arity "$#" 1 1 'release::validate_endpoint HTTPS_ENDPOINT' || return
    local label='[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?'
    local pattern="^https://${label}(\.${label})*(:([0-9]{1,5}))?(/[-a-zA-Z0-9._~]+)*/?$"
    if [[ ! "${1}" =~ ${pattern} ]]; then
        release::internal::error 64 "invalid HTTPS endpoint: ${1}"
        return 64
    fi
    # The port is capture 5: two label captures, their dotted repetition, and :port.
    local port="${BASH_REMATCH[5]:-}"
    if [[ -n "${port}" ]] && (( 10#${port} < 1 || 10#${port} > 65535 )); then
        release::internal::error 64 "invalid HTTPS endpoint: ${1}"
        return 64
    fi
}
