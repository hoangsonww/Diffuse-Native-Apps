# ADR 0004: No third-party Swift dependencies

## Status

Accepted.

## Date

2026-08.

## Context

A local-first systems tool that shells out to `git` already has a supply chain. Adding SPM packages for argument parsing, networking, or analytics would expand it for convenience.

## Decision

The Swift package graph is first-party only. The CLI uses a hand-rolled argument parser. Tests use Swift Testing (Apple). Formatting is a dev-time Homebrew tool (`SwiftFormat`), not a package dependency. Coverage is first-party `llvm-cov`.

There is no dependency bot. With no Swift packages to watch, the remaining surface is a handful of pinned Actions and the tiny npm tree for Husky, which a person bumps deliberately.

## Alternatives considered

- **swift-argument-parser, swift-log, etc.** Convenient. Rejected: extra review surface, version pins, and CI that is no longer “clone and build.”
- **A single ‘harmless’ analytics SDK.** Rejected as incompatible with [0001](0001-local-first.md).

## Consequences

- CI is hermetic: clone, bootstrap, test, build.
- Argument parsing is less fancy than ArgumentParser. That is acceptable.
- If a dependency becomes truly necessary, it requires a new ADR that supersedes this one.

## Related

[0001](0001-local-first.md), [0005](0005-generated-unsigned.md).
