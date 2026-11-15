# Contributing to neocaca

Contributions are welcome. This document describes the path from an idea
to a merged pull request. The rules themselves are set out in
[`AGENTS.md`](AGENTS.md), the single rulebook for human contributors and
coding agents alike; this document refers to it rather than repeating it,
and it should be read before a first change.

**Contents:** [Choosing the work](#choosing-the-work) ·
[Setting up](#setting-up) · [Writing the change](#writing-the-change) ·
[Opening the pull request](#opening-the-pull-request) ·
[Other contributions](#other-contributions) · [License](#license)

## Choosing the work

- **The roadmap.** [`TODO.md`](TODO.md) lists the open work in phases, cut
  into small pieces grouped by pull request. Work begins with the first
  unticked piece; [Work in pieces](AGENTS.md#branches-pull-requests-and-commits)
  explains how pieces stack.
- **The issue tracker.** Search the
  [open issues](https://github.com/poopware-laboratories/neocaca/issues)
  before starting: the work may already be in progress, or the issue may
  specify how it should be done. Claim an issue by commenting on it.
- **New proposals.** For anything on neither list, open an issue first
  that describes the change and the reason for it. This matters most for
  new key bindings, new dependencies (which require the maintainers'
  agreement) and anything that changes how files are saved.

## Setting up

The only requirement is [Zig 0.17.1](https://ziglang.org/download/),
exactly the version pinned in `build.zig.zon`; `zig build` fetches and
compiles mimalloc itself.

```sh
git clone https://github.com/poopware-laboratories/neocaca
cd neocaca
zig build test --summary all     # every test; all must pass
zig build run -- README.md       # try the editor
```

The remaining commands (test filters, release builds, cross-compilation,
benchmarks) are listed in the [quick reference](AGENTS.md#quick-reference).

## Writing the change

1. **Write the test first** and confirm that it fails for the expected
   reason. Then write the least code that makes it pass, and refactor
   with the whole suite green. See
   [strict test-driven development](AGENTS.md#workflow-strict-test-driven-development).
2. **Add three lines of tests for each line of production code.** Edge
   cases, limits, malformed input and allocation failures count; padding
   does not. [The 3:1 rule](AGENTS.md#workflow-strict-test-driven-development)
   defines what is counted. CI counts it on every pull request, and
   `zig build ratio` counts it locally.
3. **Work from specifications.** Never read, port or copy the source code
   of another editor or library, even for comparison. Specifications,
   user manuals and one's own experiments are permitted. See the
   [clean-room policy](AGENTS.md#clean-room-policy).
4. **Keep the documentation current** in the same pull request: tick or
   add items in `TODO.md`, update [`docs/keys.md`](docs/keys.md) when a
   binding changes, and update the architecture table in `AGENTS.md` when
   files move.

Before pushing, run `zig build fmt` and then the checks CI runs
(formatting, the tests in Debug and ReleaseSafe, and the other targets),
which are listed in the [quick reference](AGENTS.md#quick-reference).

> [!TIP]
> For any change to what the screen shows, also run the editor and
> inspect the result, as [Verifying UI changes](AGENTS.md#verifying-ui-changes)
> describes. A change that adds something users do (a command, a mode, a
> file type) also adds its scenario to
> [`docs/field-validation.md`](docs/field-validation.md), so that the next
> field validation pass exercises it on real work.

## Opening the pull request

| Item | Requirement |
|------|-------------|
| Branch | From an up-to-date `main`, named `type/short-topic` (for example `fix/undo-merge`) |
| Title | A [Conventional Commit](https://www.conventionalcommits.org/en/v1.0.0/), such as `fix(edit): keep the cursor column on undo`; it becomes the single squashed commit on `main` |
| Description | [The template](.github/pull_request_template.md), completed: why the change is needed, `Closes #N`, and how it was verified (benchmarks for performance work, screen captures for rendering) |
| Scope | One concern per pull request; a large change is usually better split into several small ones, each easier to review and to test |

Every CI check must pass before a merge. `main` requires the `ci` job,
which starts with the others, waits for them, and passes only when every
lint, test, build and benchmark job has passed, and the `title` check. The details are in
[Branches, pull requests and commits](AGENTS.md#branches-pull-requests-and-commits).

## Other contributions

- **Bug reports.** Open an issue with the file contents or keys that cause
  the problem, the terminal emulator used, and the expected behavior. A
  sequence of keys from a fresh start is the most useful report possible.
- **Security problems** are reported privately, never in a public issue;
  see [`SECURITY.md`](SECURITY.md).
- **Accessibility.** Users of screen readers, magnifiers, alternative
  keyboards or high-contrast themes are invited to report whatever
  hinders them; see [`ACCESSIBILITY.md`](ACCESSIBILITY.md).

## License

neocaca is licensed under the
[GNU Affero General Public License v3.0](LICENSE). Contributions are
accepted under the same terms.
