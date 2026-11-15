<div align="center">

# neocaca

**A modern modal code editor for the terminal, written in Zig.**

*Fast where it counts, careful everywhere else.*

[![CI](https://github.com/poopware-laboratories/neocaca/actions/workflows/ci.yml/badge.svg)](https://github.com/poopware-laboratories/neocaca/actions/workflows/ci.yml)
[![Zig 0.17.1](https://img.shields.io/badge/zig-0.17.1-f7a41d?logo=zig&logoColor=white)](https://ziglang.org/download/)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

[Overview](#overview) ·
[Design principles](#design-principles) ·
[Performance and security](#performance-and-security) ·
[Getting started](#getting-started) ·
[Architecture](#architecture) ·
[Contributing](#contributing)

</div>

> [!WARNING]
> **neocaca is in early development.** It edits one file at a time with
> Kakoune-style modal keys, multiple selections, regular-expression search
> and undo, and it saves atomically. Syntax highlighting, configuration
> and multiple buffers are not yet available. The roadmap is
> [`TODO.md`](TODO.md); the
> [issue tracker](https://github.com/poopware-laboratories/neocaca/issues)
> lists work that is open to contributors.

## Overview

neocaca is a terminal (TUI) code editor that speaks to the terminal
directly: it sets raw mode itself, decodes the bytes the terminal sends,
and writes only the escape sequences needed to update the screen. It keeps
its own text buffer, input decoder and screen renderer, each of which is
tested without a real terminal.

Editing follows the selection-first model popularized by Kakoune: a
selection is made first, and a verb then acts on it, so the text a command
will change is always visible before the command runs. Multiple
selections are first-class: every motion, text object and verb applies to
all of them at once.

## Design principles

Every part of neocaca is held to the following commitments.

| Principle | In practice |
|-----------|-------------|
| **Files are never lost** | Saves are atomic, every edit can be undone, and a crash never truncates a file. Unsaved changes are written to a recovery file when the terminal closes. |
| **File contents are untrusted** | Escape sequences and control bytes in a file are displayed visibly and never written to the terminal raw, so opening a file cannot reprogram the terminal. |
| **Speed where it matters** | Text scanning uses SIMD, the screen is redrawn only where it changed, saves and loads run off the event loop, and the release allocator is [mimalloc](https://github.com/microsoft/mimalloc). Very large files are the next step: today every edit rebuilds the whole text (see [`TODO.md`](TODO.md)). |
| **Self-contained** | A single binary, built from the Zig standard library and mimalloc alone. |
| **Test-first** | Every behavior begins as a failing test, and every pull request adds at least three lines of tests for each line of production code. |

## Performance and security

Speed is never obtained by removing safety checks. neocaca ships as
**ReleaseSafe**, with bounds and overflow checks enabled, and its fast
paths are written so that those checks remain enabled without slowing
them down.

| Layer | Performance | Safety |
|-------|-------------|--------|
| Text scanning (`src/simd`) | `@Vector` kernels at the CPU's widest vector width | Reads only through bounds-checked slices, never past the end of the input; each kernel is checked against a scalar reference on random input and at every vector boundary |
| Allocation (`src/alloc`) | mimalloc in every release mode | mimalloc's hardening is on by default (guard pages, randomized addresses, double-free and free-list corruption detection); a leak-checking allocator is used in Debug builds and tests |
| Rendering (`src/render`) | Only changed cells are redrawn | Control bytes from files are made visible and never sent to the terminal |

### Scanning throughput

Scanning 64 MiB of text in ReleaseSafe with the hardened mimalloc
(`zig build bench -Dbench-optimize=safe`, x86-64 with AVX2). The machine
is a shared cloud host, so individual runs vary by a few GiB/s.

| Kernel | Scalar | SIMD |
|--------|-------:|-----:|
| Count newlines | 2.1 GiB/s | 16.4 GiB/s |
| Find a byte | 4.0 GiB/s | 23.7 GiB/s |
| Find a control byte | 2.1 GiB/s | 13.8 GiB/s |
| Find a non-ASCII byte | 3.3 GiB/s | 22.9 GiB/s |

ReleaseFast performs at about the same speed: the kernels' loops let the
compiler prove their bounds checks redundant, so it removes them itself.

### Compared with flow

neocaca measures itself against [flow](https://flow-control.dev), another
terminal editor written in Zig (`zig build compare`, on a pseudo-terminal,
against flow 0.7.2):

| Measurement | neocaca | flow |
|-------------|--------:|-----:|
| First frame | 3.4 ms | 13.3 ms |
| Response to a key | 0.66 ms | 1.94 ms |
| Opening a 100 MiB file | 403 ms, 232 MiB | 876 ms, 703 MiB |
| Typing at 10,000 cursors | under 5 ms | about 500 ms |

neocaca still uses more memory at startup, and it refuses files larger
than 256 MiB, which flow opens. The complete table, and the features flow
offers that neocaca does not yet, are kept under "The yardstick" in
[`TODO.md`](TODO.md).

What neocaca treats as untrusted, the limits it enforces, and how to
report a vulnerability are described in [`SECURITY.md`](SECURITY.md).

## Getting started

### Requirements

[Zig 0.17.1](https://ziglang.org/download/). `zig build` fetches and
compiles mimalloc from source; neither CMake nor any system package is
required.

### Building and running

```sh
git clone https://github.com/poopware-laboratories/neocaca
cd neocaca
zig build -Doptimize=safe            # builds zig-out/bin/neocaca
./zig-out/bin/neocaca --help
./zig-out/bin/neocaca src/main.zig   # opens a file
```

### First steps

Editing is modal and selection-first: select, then act.

| Keys | Effect |
|------|--------|
| `w`, then `d` | Select a word, then delete it |
| `%`, `s` *regex* Enter, `c` | Select the whole buffer, select every match in it, then change them all at once |
| `i` … Esc | Type at every cursor, then return to normal mode |
| `u` / `U` | Undo / redo |
| `:w`, `:q`, `:wq` | Write, quit, or both |

Every binding is documented in [`docs/keys.md`](docs/keys.md).

### Build commands

| Command | Purpose |
|---------|---------|
| `zig build` | Debug build, with the leak-checking allocator |
| `zig build -Doptimize=safe` | The shipping build (ReleaseSafe) |
| `zig build -Dtarget=aarch64-macos` | Cross-compilation (Linux, macOS, FreeBSD) |
| `zig build -Dmimalloc-secure=off\|on\|full` | mimalloc hardening level (default `on`) |
| `zig build test --summary all` | Every test |
| `zig build test -Dtest-filter="name"` | Only the tests whose names match |
| `zig build test -fincremental --watch` | Rerun the tests incrementally on every save (x86_64-linux) |
| `zig build fmt` | Format the sources (`fmt-check` only checks) |
| `zig build bench` | SIMD kernels against their scalar references |
| `zig build compare -Dflow=<path>` | neocaca against flow on a pseudo-terminal |
| `zig build ratio -- <diff>` | The 3:1 test rule counted over a diff, as CI counts it |

### Installing locally

Until packages are published, neocaca can be installed to
`/usr/local/bin`. Run these targets as an ordinary user; `sudo` (or
`doas`) is requested only for the final copy.

| Command | Purpose |
|---------|---------|
| `make install` | The shipping build with link-time optimization, installed |
| `make optimized-install` | The same build, laid out again by `llvm-bolt` from scripted editing sessions, installed (Linux; requires `llvm-bolt`, `merge-fdata` and `tmux`) |
| `make bolt-use FILE=x` | Edit with the instrumented build; quitting adds the session to the profile that `make optimized-install` uses |
| `make bolt-compare` | CPU time of the scripted sessions with and without BOLT (requires `perf`) |
| `make uninstall` | Remove the installed binary |

`PREFIX` and `DESTDIR` are honored. Zig 0.17 accepts no compiler profile,
so BOLT provides the profile-guided step; `scripts/bolt.sh --help`
describes it in detail.

## Architecture

```
terminal bytes ──► term::Tty ──► app::loop ──► app::Session ──► input::Decoder ──► input::keymap
                                                    │ fs::file (saves, loads            │
                                                    │  on their own threads)            ▼
                                                    └──────────────────────────► app::Editor ──► edit::Document
                                                                                                      │
terminal ◄── render::diff ◄── render::Screen ◄── app::layout ◄── ui ◄─────────────────────────────────┘
```

A pure core (buffers, editing, input decoding, layout and screen diffing)
is tested without a terminal and sits behind a thin layer that performs
the I/O. Each subsystem is a folder of small, single-purpose files behind
one namespace file (`src/cli.zig` and `src/cli/`). The complete layout is
documented in [`AGENTS.md`](AGENTS.md#architecture-in-one-screen).

| Path | Contents |
|------|----------|
| `src/main.zig` | Process setup only, then `app.run` |
| `src/app/` | The editor state, its event loop, and the session that joins it to the terminal and to files |
| `src/cli/` | Commands, parsing and help text |
| `src/alloc/` | mimalloc as a `std.mem.Allocator`, and the process allocator for each build mode |
| `src/simd/` | One file per kernel: byte counting, byte search, control-byte search, printable-ASCII runs |
| `src/bench/` | `zig build bench` (kernels against their scalar references) and `zig build compare` (neocaca against flow) |
| `src/compare/` | The pure part of `zig build compare`: terminal replies, frame waits, test files, the results table |
| `src/ratio/` | The 3:1 rule over a diff: its added lines, which of them are tests, the tally |
| `src/release/` | Releases: versions, Conventional Commit messages, whether a release is due, its changelog section and the files it changes |
| `src/tools/` | `zig build ratio` (the 3:1 count over a diff file) and `zig build release` (the release steps) |
| `src/unicode/` | UTF-8 decoding that never fails, display widths, characters with combining marks, visible control bytes |
| `src/buffer/` | Text with a line index, change sets, and a file's CRLF line ends, byte order mark and missing final newline |
| `src/regex/` | A linear-time, bounded regular-expression engine (Pike VM) |
| `src/edit/` | Selections, motions, text objects, verbs, registers, search and undo |
| `src/input/` | Terminal bytes to keys, and the Kakoune-style keymap |
| `src/render/` | The cell grid, styles, and the difference between frames as escape bytes |
| `src/ui/` | Gutter, text, status line, prompt and scrolling |
| `src/term/` | Raw mode, size, input waits, resizes, suspending (Ctrl-z or SIGTSTP) and continuing (SIGCONT), hang-ups and SIGTERM, and restoring the terminal on exit and on panic |
| `src/fs/` | Bounded loads, and atomic saves that keep permissions, owner, group and symbolic links and refuse to split hard links |
| `tests/` | Whole editing sessions driven by scripted keys, and the editor on a pseudo-terminal |
| `scripts/` | The corpus that a field validation pass edits ([`docs/field-validation.md`](docs/field-validation.md)) and the local install scripts |

## Contributing

[`AGENTS.md`](AGENTS.md) is the single rulebook for human contributors and
coding agents alike, and should be read before a first change. In brief:

1. **Red.** Write a test, run it, and confirm that it fails for the
   expected reason.
2. **Green.** Write the least code that makes it pass.
3. **Refactor** with the whole suite green, then run `zig build fmt` and
   the tests in Debug and ReleaseSafe.
4. **Open a pull request** whose title is a
   [Conventional Commit](https://www.conventionalcommits.org/), with at
   least three lines of tests for each line of production code.

[`CONTRIBUTING.md`](CONTRIBUTING.md) describes the process step by step.
Security problems are reported privately, as [`SECURITY.md`](SECURITY.md)
explains. [`ACCESSIBILITY.md`](ACCESSIBILITY.md) describes what works with
assistive technology today and what does not yet.

## License

neocaca is licensed under the
[GNU Affero General Public License v3.0](LICENSE). mimalloc is licensed
under the MIT License, © Microsoft Corporation.
