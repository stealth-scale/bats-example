# Security policy

## Supported versions

The `main` branch is supported. The repository publishes no releases.

## Reporting a vulnerability

Report a vulnerability through GitHub's private vulnerability reporting on this repository,
under its Security tab. Do not open a public issue. We acknowledge a report within three
working days and publish a fix before any disclosure.

## Network access

`releasectl publish` makes real HTTPS requests outside tests. The suite runs it against
mocks only: the harness replaces `curl` with a default that fails closed, and the container
tests run with `--network=none`. The README states what the client guarantees and what it
leaves to the server.
