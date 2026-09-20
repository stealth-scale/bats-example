# module: release/cli
# Dispatch only. All application behavior is callable without starting a process.

#######################################
# Dispatches the CLI, validating the exact argument count before calling a command.
# Usage: release::main [help|plan|manifest|prepare|verify|publish] [ARGUMENTS...]
# Arguments: $1 - Command, defaults to help; remaining arguments belong to the command.
# Outputs: Command results to stdout; usage errors to stderr.
# Returns: The command status, or 64 for an invalid command or argument count.
#######################################
release::main() {
    local action="${1:-help}"
    case "${action}:$#" in
        help:0|help:1|--help:1)
            printf '%s\n' 'Usage: releasectl COMMAND [ARGS]' \
                '  plan VERSION ENVIRONMENT' \
                '  manifest VERSION ENVIRONMENT' \
                '  prepare VERSION ENVIRONMENT DIRECTORY' \
                '  verify MANIFEST' \
                '  publish MANIFEST HTTPS_ENDPOINT'
            ;;
        plan:3) release::plan "${2}" "${3}" ;;
        manifest:3) release::manifest "${2}" "${3}" ;;
        prepare:4) release::prepare "${2}" "${3}" "${4}" ;;
        verify:2) release::verify "${2}" ;;
        publish:3) release::publish "${2}" "${3}" ;;
        *) release::internal::error 64 "invalid command or arguments: ${action} (see --help)" ;;
    esac
}
