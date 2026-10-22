# Contributing to neocaca

Thank you for helping. This page tells you how to get from an idea to a
merged pull request. The rules themselves live in [`AGENTS.md`](AGENTS.md),
the single rulebook for humans and coding agents alike; this page links
to it rather than repeating it, so read it before your first change.

## Find something to work on

- [`TODO.md`](TODO.md) is the roadmap, in phases. Work from the earliest
  phase with open items.
- Search the [open issues](https://github.com/poopware-laboratories/neocaca/issues)
  before you start: someone may already be on it, or the issue may say how
  it should be done. Comment on the issue to claim it.
- For something not on either list, open an issue first and say what you
  want to change and why. That matters most for new key bindings, new
  dependencies (which need maintainer agreement first) and anything that
  changes how files are saved.

## Set up

You need exactly [Zig 0.17.0](https://ziglang.org/download/), the version
pinned in `build.zig.zon`. Nothing else: `zig build` fetches and compiles
mimalloc itself.

```sh
git clone https://github.com/poopware-laboratories/neocaca
cd neocaca
zig build test --summary all     # every test; all should pass
zig build run -- README.md       # try the editor
```

The other commands (filters, release builds, cross-compiling, benchmarks)
are in the [quick reference](AGENTS.md#quick-reference).

## Write the change

1. **Write a test first** and watch it fail for the reason you expect.
   Then write the least code that makes it pass, and clean up with the
   whole suite green. See
   [strict test-driven development](AGENTS.md#workflow-strict-test-driven-development).
2. **Add three lines of tests for every line of production code.** Edge
   cases, limits, malformed input and allocation failures count; padding
   does not. [The 3:1 rule](AGENTS.md#workflow-strict-test-driven-development)
   says what is counted.
3. **Write it yourself, from specifications.** Never read, port or copy
   another editor's or library's source, even to compare. Specifications,
   user manuals and your own experiments are fine. See the
   [clean-room policy](AGENTS.md#clean-room-policy).
4. **Keep the docs in step** in the same pull request: tick or add items in
   `TODO.md`, update [`docs/keys.md`](docs/keys.md) when a binding changes,
   and update the architecture table in `AGENTS.md` when files move.

Before pushing, run what CI runs:

```sh
zig build fmt                            # format
zig build fmt-check
zig build test --summary all             # Debug
zig build test -Doptimize=safe --summary all  # ReleaseSafe, as shipped
```

For anything that changes what the screen shows, also run the editor and
look, as [Verifying UI changes](AGENTS.md#verifying-ui-changes) describes.

## Open the pull request

- Branch from an up-to-date `main` and name the branch `type/short-topic`
  (`fix/undo-merge`).
- The title is a [Conventional Commit](https://www.conventionalcommits.org/en/v1.0.0/),
  such as `fix(edit): keep the cursor column on undo`. It becomes the one
  squashed commit on `main`.
- Fill in [the template](.github/pull_request_template.md): why the change
  is needed, `Closes #N`, and how you checked it (benchmarks for
  performance work, screen captures for rendering).
- Keep one concern per pull request. A large change usually splits into
  several small ones that are each easier to review and to test.

All CI checks must pass before a merge. The details are in
[Branches, pull requests and commits](AGENTS.md#branches-pull-requests-and-commits).

## Other ways to help

- **Report a bug** in an issue, with the file contents or keys that cause
  it, the terminal you use, and what you expected to happen. A sequence of
  keys from a fresh start is the most useful report there is.
- **Report a security problem privately**, never in a public issue: see
  [`SECURITY.md`](SECURITY.md).
- **Tell us what gets in your way** if you use a screen reader, a
  magnifier, an unusual keyboard or a high-contrast theme: see
  [`ACCESSIBILITY.md`](ACCESSIBILITY.md).

## License

neocaca is licensed under the [GNU Affero General Public License v3.0](LICENSE).
By contributing, you agree that your contributions are licensed under the
same terms.
