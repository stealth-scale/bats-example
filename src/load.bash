# releasectl library loader. Importing defines functions; it performs no work.
# Shell options, traps and the working directory belong to the caller.

# shellcheck source=src/release/runtime.bash
source "${BASH_SOURCE[0]%/*}/release/runtime.bash" || return
release::internal::require_bash "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" || return
# shellcheck source=src/release/validation.bash
source "${BASH_SOURCE[0]%/*}/release/validation.bash" || return
# shellcheck source=src/release/policy.bash
source "${BASH_SOURCE[0]%/*}/release/policy.bash" || return
# shellcheck source=src/release/manifest.bash
source "${BASH_SOURCE[0]%/*}/release/manifest.bash" || return
# shellcheck source=src/release/bundle.bash
source "${BASH_SOURCE[0]%/*}/release/bundle.bash" || return
# shellcheck source=src/release/publish.bash
source "${BASH_SOURCE[0]%/*}/release/publish.bash" || return
# shellcheck source=src/release/cli.bash
source "${BASH_SOURCE[0]%/*}/release/cli.bash"
