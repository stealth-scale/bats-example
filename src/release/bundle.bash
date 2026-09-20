# module: release/bundle
# Private staging beside the destination, followed by a no-clobber rename.
# The destination parent must be trusted; this is not a hostile-filesystem sandbox.

#######################################
# Builds a complete bundle before publishing its directory. Never replaces a path.
# GNU mv -T -n prevents an existing directory from swallowing the staging directory.
# Usage: release::prepare v1.2.3 production /tmp/release-bundle
# Arguments: $1 - Version; $2 - Environment; $3 - New directory, parent must exist.
# Outputs: manifest.json and plan.txt (0600) in a private directory (0700).
#          The requested destination to stdout only after publication succeeds.
# Returns: 0 on success; 64 for invalid input; 73 for an existing path; I/O status otherwise.
#######################################
release::prepare() (
    release::internal::arity "$#" 3 3 'release::prepare VERSION ENVIRONMENT DIRECTORY' || return
    local manifest plan destination="${3%/}" parent stage
    [[ -n "${destination}" ]] || { release::internal::error 64 'missing destination'; return 64; }
    manifest=$(release::manifest "${1}" "${2}") || return
    plan=$(release::plan "${1}" "${2}") || return
    if [[ -e "${destination}" || -L "${destination}" ]]; then
        release::internal::error 73 "destination already exists: ${destination}"
        return 73
    fi
    parent=$(dirname -- "${destination}") || return
    umask 077
    stage=$(mktemp -d -- "${parent}/.releasectl.XXXXXXXX") || return
    # The only recursive removal is the fresh directory allocated by mktemp above.
    trap '[[ -z ${stage:-} ]] || rm -rf -- "${stage}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '%s\n' "${manifest}" > "${stage}/manifest.json" || return
    printf '%s\n' "${plan}" > "${stage}/plan.txt" || return
    mv -T -n -- "${stage}" "${destination}" || return
    # Some GNU mv versions return success after skipping a no-clobber move.
    if [[ -d "${stage}" ]]; then
        release::internal::error 73 "destination already exists: ${destination}"
        return 73
    fi
    stage=''
    printf '%s\n' "${3}"
) # LCOV_EXCL_LINE: kcov v43 counts this syntax delimiter; Bash never traces it.
