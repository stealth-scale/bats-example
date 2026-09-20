# module: release/policy
# One source for deployment targets, capacity and bounded retry budgets.

#######################################
# Normalizes a version into a caller-owned scalar, silently.
# Usage: release::version normalized v1.2.3
# Arguments: $1 - Output variable name; $2 - Version tag.
# Outputs: The named variable, with the leading v removed.
# Returns: 0 on success; 64 on invalid input, without changing the output.
#######################################
release::version() {
    release::internal::arity "$#" 2 2 'release::version VARIABLE VERSION' || return
    release::internal::output_name "${1}" || return
    release::validate_version "${2}" || return
    local -n _release_version_out="${1}"
    _release_version_out=${2#v}
}

#######################################
# Returns ordered deployment targets through an indexed-array nameref.
# Usage: release::targets selected production
# Arguments: $1 - Output array name; $2 - Environment.
# Outputs: The named array, replacing its previous contents.
# Returns: 0 on success; 64 on invalid input, without changing the array.
#######################################
release::targets() {
    release::internal::arity "$#" 2 2 'release::targets ARRAY ENVIRONMENT' || return
    release::internal::output_name "${1}" || return
    release::validate_environment "${2}" || return
    local -n _release_targets_out="${1}"
    if [[ "${2}" == staging ]]; then
        _release_targets_out=(preview)
    else
        _release_targets_out=(eu-west us-east)
    fi
}

#######################################
# Returns the policy through a caller-declared associative array.
# Usage: local -A policy=(); release::settings policy production
# Arguments: $1 - Associative array name; $2 - Environment.
# Outputs: The named array, with replicas and attempts keys.
# Returns: 0 on success; 64 on invalid input, without changing the array.
#######################################
release::settings() {
    release::internal::arity "$#" 2 2 'release::settings ARRAY ENVIRONMENT' || return
    release::internal::output_name "${1}" || return
    release::validate_environment "${2}" || return
    local -n _release_settings_out="${1}"
    # shellcheck disable=SC2154  # keys of the caller-declared associative array
    if [[ "${2}" == staging ]]; then
        _release_settings_out=([replicas]=1 [attempts]=2)
    else
        _release_settings_out=([replicas]=3 [attempts]=3)
    fi
}

#######################################
# Prints a four-line plan using the same policy as manifest generation and upload.
# Usage: release::plan v1.2.3 production
# Arguments: $1 - Version tag; $2 - Environment.
# Outputs: The plan to stdout; diagnostics to stderr.
# Returns: 0 on success; 64 for invalid input.
#######################################
release::plan() {
    release::internal::arity "$#" 2 2 'release::plan VERSION ENVIRONMENT' || return
    local version
    local -a targets=()
    local -A settings=()
    release::version version "${1}" || return
    release::targets targets "${2}" || return
    release::settings settings "${2}" || return
    printf 'release: %s\nenvironment: %s\nreplicas: %s\ntargets: %s\n' \
        "${version}" "${2}" "${settings[replicas]}" "${targets[*]}"
}
