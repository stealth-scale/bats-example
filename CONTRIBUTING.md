# Contributing

This repository demonstrates application testing. Keep examples focused on
observable behavior rather than duplicating the helpers' internal suites.

## Check a change

```sh
git submodule update --init --recursive
make check
make coverage DISTRO=fedora
make test-host
```

Container tests support Podman and Docker. Host tests additionally require Bash 4.4+,
GNU coreutils, jq and bats-core 1.7+ on PATH. Use the shared image when you need a
network-isolated or version-specific run. On macOS, follow the README's selective
GNU `mv`/`timeout` setup and keep native `stat`; do not replace the whole userland.

## Code and test conventions

- Keep the executable thin. Source `src/load.bash`; put behavior in the appropriate
  `src/release/` module. Imports must stay silent and preserve caller shell state.
- Document each function's usage, arguments, outputs and return statuses. Validate
  argument counts before expansion under nounset; print diagnostics to stderr.
- Quote expansions, use arrays for argument lists and namerefs for caller-owned
  results. Do not evaluate user input as shell code.
- Propagate command failures explicitly. Do not rely on errexit: callers may invoke
  a function from an `if`, `!` or `||` context.
- Limit recursive cleanup to a directory this operation allocated with `mktemp`.
  Never remove or replace the caller's destination. Isolate temporary options,
  traps and umask changes in a subshell.
- Name tests `subject: case -> expectation`. Load the named `example` harness and
  explicitly call `common_setup`/`common_teardown` from the Bats hooks.
- Keep expectations visible in the test. Share domain setup and composed assertions,
  not large scenario runners. Use real JSON/filesystem behavior; replace uploads
  and retry waits. A spy is appropriate only when executing the dependency is safe.
- Include boundary and failure cases, not just successful inputs. Verify untouched
  destinations, scratch cleanup, call counts and no subsequent work after failure.
  Use a bounded watchdog for tests that could hang.
- Keep comments about intent and contracts. Add ShellCheck suppressions only at
  the relevant statement, with a reason.

`examples/failures.bats` intentionally fails and is excluded from normal discovery.
`make test-reports` validates the exit status, TAP cases and assertion diagnostics,
so setup failures cannot masquerade as useful examples. Keep that checker aligned
when changing demonstrations.

Coverage has a 100% line floor for application modules. Do not add exclusions to hide
missing behavior; assertions and meaningful failure tests matter more than the
percentage. Run the supported Bash/Bats combinations before changing compatibility
assumptions.

The sole coverage annotation is on the closing subshell delimiter in
`src/release/bundle.bash`: kcov v43 classifies that `)` as code although Bash cannot
trace it. It excludes no executable statement. Remove it when the image's parser
handles this syntax.

## Initial repository bootstrap

This section is only for creating the repository from the initial local example,
not for a normal clone. The prepared `.gitmodules` file alone does not create
submodules: Git must record each helper as a gitlink.

Run these commands yourself from `bats-example/`. If the directory is not already
a Git repository, run `git init -b main` first.

```sh
git submodule add https://github.com/stealth-scale/bats-expect.git tests/helpers/bats-expect
git submodule add https://github.com/stealth-scale/bats-mock.git tests/helpers/bats-mock
git submodule add https://github.com/stealth-scale/bats-matrix.git tests/helpers/bats-matrix

git -C tests/helpers/bats-expect checkout --detach v1.0.1
git -C tests/helpers/bats-mock checkout --detach v1.2.1
git -C tests/helpers/bats-matrix checkout --detach v1.0.1

git add .gitmodules tests/helpers/bats-expect tests/helpers/bats-mock tests/helpers/bats-matrix
make check
make coverage DISTRO=fedora
```

Commit the recorded gitlinks together with the example's source, tests and
configuration when ready. Do not copy sibling helper checkouts into these paths:
that loses the dependency revision recorded by Git.

## Dependency updates

A normal clone uses `git submodule update --init --recursive` to restore the
recorded revisions, not the latest upstream branches. Dependabot proposes weekly
updates to gitlinks and GitHub Actions.

For a deliberate manual update, fetch and check out the selected revision inside
the relevant helper submodule, test the application, then stage the parent gitlink.
Do not change helper source here or commit generated `.deps/` or `coverage/` files.
The Makefile's `check-helpers` only checks availability; it never fetches or rewrites
dependencies.

## Commits

Use Conventional Commits with a short, imperative subject and a useful scope:

```text
feat(example): validate manifests before publishing
fix(publish): preserve the request body across retries
test(bundle): cover competing release writers
docs(example): explain direct calls and run subshells
```

Explain the behavioral reason in the body when it is not apparent from the subject.
