---
name: steward
description: Use when driving an open neocaca pull request to green - CI failures, title or test-ratio problems, review comments, or merge conflicts with main.
---

# Stewarding a neocaca pull request

## Conventions

- **Your own branch:** pick up `main` by rebasing
  (`git pull --rebase origin main`, then `git push --force-with-lease`),
  as AGENTS.md says. **Someone else's branch:** merge `main` in; never
  rewrite their history.
- `build.zig.zon` conflicts: keep `main`'s `minimum_zig_version` and
  dependency hashes, then `zig build` to confirm.
- Merging is squash only, once every check is green and the maintainer
  says *merge*. Until then the pull request stays open for the next piece
  (AGENTS.md, "Work in pieces").
- Be proactive on CI and review bots; ask before widening the pull request.

## Reproducing CI failures locally

| Failing step | Run locally |
|--------------|-------------|
| Format | `zig build fmt-check` (fix: `zig build fmt`) |
| Tests (Debug) | `zig build test --summary all` |
| Tests (ReleaseSafe) | `zig build test -Doptimize=safe --summary all` |
| Cross-target build | `zig build -Dtarget=<triple>` with the job's triple |
| Leak reported by a test | Run that test alone with `-Dtest-filter`; see managing-memory |
| Pull request title | Fix it on the PR: `type(scope): summary`, lower case, no final period |
| 3:1 ratio | Add real tests; see test-driven-development. Never pad. |

Use the Zig version from `build.zig.zon`: a failure that only reproduces
on another version is a version mismatch, not a fix to make.

## Hung tests

CI runs the tests with `--test-timeout 3m`, and each test job stops at 45
minutes. A test that hangs is killed and named in the log, and the rest
still run; reproduce it with `-Dtest-filter` and the same flag. A job that
reaches its 45 minutes means the build itself hung, not a test.

A failure only on macOS or in `qemu-aarch64` is often aarch64 itself:
reproduce it on Linux with `sudo apt-get install qemu-user`, then
`zig build test -Dtarget=aarch64-linux-musl -Doptimize=safe -fqemu`.

## Flaky tests

Tests touching processes, timing or the real terminal are the usual
suspects. "Flaky" is not a root cause: find the race (fixed sleeps,
unread pipes, ordering) and make the test wait on a condition, or move the
logic into a pure function. Never skip or loosen a test to get green.

## Before every push

`zig build fmt-check`, the tests in Debug and ReleaseSafe, cross-target builds
when platform-gated code changed, and a recount of the test ratio.
