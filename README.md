# bats-example

A small release CLI with a substantial test suite. It shows how three
[bats-core](https://github.com/bats-core/bats-core) helpers work together:

- [bats-expect](https://github.com/stealth-scale/bats-expect) asserts output, JSON,
  files, permissions, scalar state, arrays and nameref results.
- [bats-matrix](https://github.com/stealth-scale/bats-matrix) exercises tables of
  inputs, policies and expected failures.
- [bats-mock](https://github.com/stealth-scale/bats-mock) replaces commands, sequences
  failures, spies on real behavior, and verifies exact arguments, stdin and call order.

The application, `releasectl`, plans releases, prepares bundles, validates manifests
and uploads them. Tests exercise real JSON encoding and real files. Uploads and retry
sleeps are mocked; running the suite deploys nothing.

## Run the tests

This project uses helper submodules and the shared
[bats-test](https://github.com/stealth-scale/bats-test) image, following the same
integration as `stealthos-lib`. Clone it with its submodules:

```sh
git clone --recurse-submodules https://github.com/stealth-scale/bats-example.git
cd bats-example
make test                         # Podman
make test RUNTIME=docker           # Docker
make test TARGET=tests/publish.bats
make test-reports                 # Verifies the deliberately failing examples
```

In an existing clone, `git submodule update --init --recursive` restores the helpers.
Make never installs dependencies or changes Git state.

Container tests use a read-only checkout, no network and no Linux capabilities.
Only the coverage target mounts its report directory writable. The image is pulled
by the runtime when needed; no local image build is required.

For host tests, install Bash 4.4+, GNU make, GNU coreutils, jq and bats-core 1.7+,
then run `make test-host`. On macOS, use Homebrew Bash and expose only GNU `mv`
and `timeout`; leave the native `stat` available to the permission assertions.
Do not prepend coreutils' whole `libexec/gnubin` directory to `PATH`.
Apple's Bash 3.2 and BSD `mv` are not supported. With the tools installed:

```sh
coreutils_bin="$(brew --prefix coreutils)/bin"
host_tools=$(mktemp -d)
ln -s "$coreutils_bin/gmv" "$host_tools/mv"
ln -s "$coreutils_bin/gtimeout" "$host_tools/timeout"
PATH="$host_tools:$(brew --prefix)/bin:$PATH" make test-host
```

ShellCheck is needed for `make lint`. Host tests have mock guards against accidental
uploads, but only the container provides network isolation.

## Start with these examples

| Learn | Tests |
| --- | --- |
| Table-driven inputs, multiline output, regex and custom delimiters | [plan.bats](tests/plan.bats) |
| Scalar, indexed-array and associative-array namerefs | [state.bats](tests/state.bats) |
| JSON encoding and policy-derived manifest generation | [manifest.bats](tests/manifest.bats) |
| Closed-schema validation, malformed documents and inconsistent fields | [verify.bats](tests/verify.bats) |
| Real files, permissions, symlinks, failure cleanup and competing writers | [bundle.bats](tests/bundle.bats) |
| Retry sequences, exact argv/stdin, concurrency, signals and immutable payloads | [publish.bats](tests/publish.bats) |
| Call-through functions and executables, pipelines and mock restoration | [spies.bats](tests/spies.bats) |
| The executable, dispatch, stderr and mocks inherited by a child Bash | [cli.bats](tests/cli.bats) |
| Argument contracts, safe output names and side-effect-free imports | [runtime.bats](tests/runtime.bats) |
| Rejecting false positives in the diagnostic checker | [reports.bats](tests/reports.bats) |

### One named harness

Each test file starts with the same explicit lifecycle:

```bash
bats_load_library example
setup() { common_setup; }
teardown() { common_teardown; }
```

[The harness](tests/helpers/example/load.bash) loads the three helpers through
`BATS_LIB_PATH`, sources the application and creates a separate mock session per
test. It replaces `curl` with a fail-closed default and `sleep` with a no-wait
response. Files and scratch space live under `BATS_TEST_TMPDIR`; teardown restores
mocks and removes their owned state.

The Makefile discovers application suites while excluding `tests/helpers/` and
the intentional failures. Do not use an unfiltered `bats --recursive tests/`:
that would also discover the submodules' own tests.

### All three helpers in one test

The retry-policy test in [publish.bats](tests/publish.bats) creates real bundles,
runs both environments through a matrix, then checks the shared call history and JSON:

```bash
prepare_bundle production
local staging="$BATS_TEST_TMPDIR/staging bundle"
release::prepare v1.2.3 staging "$staging" >/dev/null
mock curl '*' 'cat >/dev/null; return 7'

run_matrix release::publish <<CASES
    $staging/manifest.json    | $API_URL | 7 | EMPTY
    $BUNDLE_DIR/manifest.json | $API_URL | 7 | EMPTY
CASES

assert_called_times curl 5
assert_called_times sleep 3
assert_call_sequence curl sleep curl curl sleep curl sleep curl
assert_json_equal --file "$staging/manifest.json" .environment staging
assert_json_equal --file "$BUNDLE_DIR/manifest.json" .environment production
```

A matrix is one Bats test, not one test per row. Each row runs in a subshell, and
the first mismatch stops the matrix. Mock history survives those subshells.
The unquoted here-document above expands trusted test paths; use a quoted delimiter
when the rows must remain literal.

### Spy when the real behavior matters

```bash
local -a selected=()
mock_spy release::targets

release::targets selected production

assert_array_equal selected eu-west us-east
assert_called_with_args release::targets selected production
```

Call directly when asserting changes to the caller's variables. Bats `run` creates
a subshell, so its variable changes do not propagate back. Spies execute real behavior:
spying on `curl` would not prevent a network request. Function mocks intercept normal
Bash command resolution, not absolute executable paths or deliberate `command curl`
bypasses.

### Check the failure reports too

`make test-reports` succeeds only when all three demonstrations fail with their
expected JSON, matrix and mock diagnostics. A broken setup or unexpectedly passing
example fails this check.

To inspect the reports yourself:

```sh
make test TARGET=examples/failures.bats
make test-host TARGET=examples/failures.bats
```

These two commands intentionally exit nonzero. Normal `make test` must pass.

## Try the application

The application needs Bash 4.4+, GNU coreutils and jq; publishing also needs curl.

```bash
./bin/releasectl plan v1.2.3 production
./bin/releasectl manifest v1.2.3 staging

demo_dir=$(mktemp -d)
./bin/releasectl prepare v1.2.3 production "$demo_dir/bundle"
./bin/releasectl verify "$demo_dir/bundle/manifest.json"
jq . "$demo_dir/bundle/manifest.json"
```

Supported versions are `vMAJOR.MINOR.PATCH` and `vMAJOR.MINOR.PATCH-rc.N`, without
leading zeros; `N` starts at 1. Environments are `staging` and `production`.

### Application guarantees and boundaries

- **One policy:** staging uses one replica, the `preview` target and two upload
  attempts; production uses three replicas, `eu-west`/`us-east` and three attempts.
- **Validated manifests:** `verify` accepts exactly one JSON object matching schema 1
  and the derived policy. Unknown keys, wrong types and inconsistent fields fail.
  Whitespace and object-key order do not matter.
- **Complete bundles:** `prepare` stages both files beside the destination, then uses
  a no-clobber directory rename. Directories are 0700 and files 0600. Existing files,
  directories and symlinks are preserved; concurrent writers cannot merge bundles.
- **Stable request bodies:** `publish` copies the manifest to private scratch space,
  validates that snapshot and reopens the same bytes on every attempt. A caller
  changing the original file between attempts cannot change the retried payload.
- **Bounded retries:** only curl transport statuses 6, 7, 18, 28, 52, 55 and 56 are
  retried, with a one-second delay. HTTP errors, TLS failures and local errors stop
  immediately. Each attempt has a two-second connection timeout and a five-second
  total timeout. Failed response bodies never appear on stdout.
- **Scoped cleanup:** EXIT, INT and TERM clean owned staging/scratch directories.
  Shell options, traps and umask changes stay inside the operation's subshell.

`releasectl publish MANIFEST HTTPS_ENDPOINT` makes **real requests outside tests**.
It appends `/releases` to an HTTPS DNS/IPv4 endpoint with an optional port/base path.
Credentials in URLs, query strings, fragments, IPv6 and percent escapes are intentionally
unsupported. Curl config-file loading is disabled, TLS verification stays enabled,
and redirects are not followed.

The server must honor `Idempotency-Key: ENVIRONMENT/VERSION`; the client alone cannot
guarantee exactly-once processing. Bundle publication assumes a trusted parent
directory and the local filesystem's rename semantics. It is not a hostile-filesystem
sandbox or a crash-durability guarantee; SIGKILL can leave staging files behind.
This is a reference application, not a complete deployment service: authentication,
HTTP-status-specific backoff, response-size limits and retention are outside its scope.

## Code layout and checks

`bin/releasectl` enables strict shell options and dispatches through `src/load.bash`.
Importing that loader defines functions without changing the caller's options,
traps, working directory or umask.

| Module under `src/release/` | Responsibility |
| --- | --- |
| `runtime.bash` | Bash compatibility, argument counts, diagnostics and output names |
| `validation.bash` | Version, environment and endpoint validation |
| `policy.bash` | Nameref APIs, deployment settings and text plans |
| `manifest.bash` | JSON generation and contract validation |
| `bundle.bash` | Private staging and no-clobber publication |
| `publish.bash` | Payload snapshots, transport policy and cleanup |
| `cli.bash` | Exact-arity command dispatch |

Public functions document arguments, outputs and return statuses. Invalid input
returns 64, an existing bundle destination returns 73, and command failures are
propagated. Nameref APIs require caller-owned variables of the documented type;
names must be plain identifiers outside the reserved `_release_` namespace.

```sh
make check                        # ShellCheck, suite and diagnostic checks
make coverage DISTRO=fedora       # kcov HTML/XML in coverage/, 100% line floor
make test DISTRO=fedora
make test BASH_VERSION=4.4 BATS_VERSION=1.7.0
make help
```

Coverage measures `src/`, not vendored helpers, the test harness or the executable
shim. Line coverage is a regression signal, not proof of complete branch coverage.

CI runs Bash 4.4, 5.1, 5.2 and 5.3 with bats-core 1.7.0 and 1.14.0, a Fedora container,
Ubuntu/macOS host jobs with both Bats versions, lint and Fedora coverage. Normal
tests and failure-report checks run in every test job.

Submodule gitlinks record exact helper revisions: bats-expect v1.0.1, bats-matrix
v1.0.1 and bats-mock v1.2.1. Dependabot proposes weekly helper and GitHub Actions
updates; see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Copyright Stealth Scale B.V.
