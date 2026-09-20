# module: release/runtime
# Internal contracts shared by the application. Nothing changes shell options.

#######################################
# Prints a literal diagnostic and returns its specified status.
# Usage: release::internal::error 64 'invalid input'
# Arguments: $1 - Status; $2 - Diagnostic, never a printf format.
# Outputs: One line to stderr.
# Returns: The supplied status.
#######################################
release::internal::error() {
    printf '%s\n' "${2}" >&2
    return "${1}"
}

#######################################
# Checks the running Bash version before loading nameref-based modules.
# Usage: release::internal::require_bash "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"
# Arguments: $1 - Major version; $2 - Minor version (integers from Bash).
# Returns: 0 for Bash 4.4+; 2 with a diagnostic otherwise.
#######################################
release::internal::require_bash() {
    if (( $1 < 4 || ($1 == 4 && $2 < 4) )); then
        release::internal::error 2 'releasectl requires Bash 4.4 or newer'
        return 2
    fi
}

#######################################
# Checks argument counts before expanding required positional arguments.
# Usage: release::internal::arity "$#" 1 1 'release::verify FILE'
# Arguments: $1 - Count; $2 - Minimum; $3 - Maximum; $4 - Usage text.
# Returns: 0 for a valid count; 64 with usage on stderr otherwise.
#######################################
release::internal::arity() {
    if (( $1 < $2 || $1 > $3 )); then
        release::internal::error 64 "usage: ${4}"
        return 64
    fi
}

#######################################
# Refuses array expressions and internal names before creating a nameref.
# Usage: release::internal::output_name normalized
# Arguments: $1 - A caller-owned identifier, outside the _release_ namespace.
# Returns: 0 for a valid name; 64 with a diagnostic otherwise.
#######################################
release::internal::output_name() {
    if [[ ! "${1}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ || "${1}" == _release_* ]]; then
        release::internal::error 64 "invalid output variable: ${1}"
        return 64
    fi
}
