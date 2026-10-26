<div align="center">

# neocaca

**A modern terminal code editor, written in Zig.**
Fast where it counts, careful everywhere else.

[![CI](https://github.com/poopware-laboratories/neocaca/actions/workflows/ci.yml/badge.svg)](https://github.com/poopware-laboratories/neocaca/actions/workflows/ci.yml)
[![Zig 0.17.0](https://img.shields.io/badge/zig-0.17.0-f7a41d?logo=zig&logoColor=white)](https://ziglang.org/download/)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

</div>

> [!WARNING]
> **Early days.** neocaca edits one file at a time with Kakoune-style
> modal keys, multiple selections, regex search and undo, and saves
> atomically. There is no syntax highlighting, configuration or multiple
> buffers yet; [`TODO.md`](TODO.md) is the roadmap. Watch the
> [issues](https://github.com/poopware-laboratories/neocaca/issues) to
> follow along, or pick one up.

## What it is built for

These are the rules every part of neocaca is held to, from the first
line of code:

- **Your files are safe.** Saves are atomic, every edit can be undone, and
  a crash never truncates a file.
- **Opening a file can't attack your terminal.** File contents are treated
  as untrusted: escape sequences and control bytes are shown visibly, never
  written to the terminal raw.
- **Fast where it matters.** Text scanning uses SIMD, the screen is
  redrawn only where it changed, saves and loads run off the event loop,
  and the release allocator is [mimalloc](https://github.com/microsoft/mimalloc).
  (Very large files are next: today every edit rebuilds the whole text,
  see [`TODO.md`](TODO.md).)
- **Small and self-contained.** One binary, the Zig standard library and
  mimalloc, nothing else.
- **Built test-first.** Every behavior starts as a failing test; pull
  requests carry three lines of tests per line of code.

## Performance and security

Speed never costs safety checks. The editor ships as **ReleaseSafe**, with
bounds and overflow checks on, and the fast paths are written so those
checks stay on without slowing them down:

| Layer | Fast | Safe |
|-------|------|------|
| Text scanning (`src/simd`) | `@Vector` kernels, the CPU's widest vectors | Reads only through bounds-checked slices, never past the end of the input; each kernel is checked against a scalar reference on random input and every vector boundary |
| Allocator (`src/alloc`) | mimalloc in every release mode | mimalloc's hardening on by default (guard pages, randomized addresses, double-free and free-list corruption detection); leak-checking allocator in Debug and tests |
| Rendering (`src/render`) | Only changed cells are redrawn | Control bytes from files are made visible, never sent to the terminal |

Scanning 64 MiB of text, in ReleaseSafe, with the hardened mimalloc
(`zig build bench -Dbench-optimize=safe`, x86-64 with AVX2, one noisy
cloud machine, so expect a spread of a few GiB/s):

| Kernel | Scalar | SIMD |
|--------|-------:|-----:|
| Count newlines | 2.1 GiB/s | 16.4 GiB/s |
| Find a byte | 4.0 GiB/s | 23.7 GiB/s |
| Find a control byte | 2.1 GiB/s | 13.8 GiB/s |
| Find a non-ASCII byte | 3.3 GiB/s | 22.9 GiB/s |

ReleaseFast runs at about the same speed: the kernels' loops let the
compiler prove their bounds checks redundant, so it removes them itself.

Against [flow](https://flow-control.dev), the Zig terminal editor
neocaca measures itself by (`zig build compare`, on a pseudo-terminal,
against flow 0.7.2), neocaca draws its first frame in 3.4 ms to flow's
13.3, answers a key in 0.66 ms to 1.94, opens a 100 MiB file in 403 ms
and 232 MiB to 876 ms and 703 MiB, and types at 10,000 cursors in under
5 ms to flow's half a second. It still loses on memory at startup and on
files past 256 MiB, which it refuses. The full table, and what flow still
has that neocaca does not, are in "The yardstick" in [`TODO.md`](TODO.md).

What is treated as untrusted, the limits on it, and how to report a
vulnerability are in [`SECURITY.md`](SECURITY.md).

## Getting started

You need [Zig 0.17.0](https://ziglang.org/download/). mimalloc is fetched
and built from source by `zig build`; no CMake or system packages needed.

```sh
git clone https://github.com/poopware-laboratories/neocaca
cd neocaca
zig build -Doptimize=safe          # zig-out/bin/neocaca
./zig-out/bin/neocaca --help
./zig-out/bin/neocaca src/main.zig  # edit a file
```

Editing is modal and selection first, as in Kakoune: select, then act.
`w` selects a word and `d` deletes it; `%` selects the whole buffer,
`s` with a regex selects every match in it, and `c` changes them all at
once; `i` types at every cursor and Esc returns to normal mode; `u` and
`U` undo and redo; `:w`, `:q` and `:wq` write and quit. Every binding is
in [`docs/keys.md`](docs/keys.md).

| Command | What it does |
|---------|--------------|
| `zig build` | Debug build, with the leak-checking allocator |
| `zig build -Doptimize=safe` | The shipping build |
| `zig build test --summary all` | Every test |
| `zig build test -Dtest-filter="name"` | Only matching tests |
| `zig build test -fincremental --watch` | Rerun the tests on every save, incrementally (x86_64-linux) |
| `zig build fmt` | Format the sources (`fmt-check` to only check) |
| `zig build bench` | SIMD against scalar throughput |
| `zig build compare -Dflow=<path>` | neocaca against flow on a pseudo-terminal |
| `zig build -Dtarget=aarch64-macos` | Cross-compile (Linux, macOS, FreeBSD) |
| `-Dmimalloc-secure=off\|on\|full` | mimalloc hardening level (default `on`) |

## How it is built

```
terminal bytes ──► term::Tty ──► app::loop ──► app::Session ──► input::Decoder ──► input::keymap
                                                    │ fs::file (saves, loads            │
                                                    │  on their own threads)            ▼
                                                    └──────────────────────────► app::Editor ──► edit::Document
                                                                                                      │
terminal ◄── render::diff ◄── render::Screen ◄── app::layout ◄── ui ◄─────────────────────────────────┘
```

A pure core (buffers, editing, input decoding, layout, screen diffing)
that tests run without a terminal, behind a thin layer that does the I/O.
Every subsystem is a folder of small single-purpose files behind one
namespace file (`src/cli.zig` and `src/cli/`).
The full layout is in [`AGENTS.md`](AGENTS.md#architecture-in-one-screen).

| Path | What it holds |
|------|---------------|
| `src/main.zig` | Process setup only, then `app.run` |
| `src/app/` | The editor state, its event loop, and the session joining it to the terminal and files |
| `src/cli/` | Commands, parsing, help text |
| `src/alloc/` | mimalloc as a `std.mem.Allocator`; per-mode process allocator |
| `src/simd/` | One file per kernel: byte counting, byte search, control-byte search, printable-ASCII runs |
| `src/bench/` | `zig build bench`: kernels against their scalar references; `zig build compare`: neocaca against flow |
| `src/compare/` | The pure part of `zig build compare`: terminal replies, frame waits, test files, the table |
| `src/unicode/` | UTF-8 that never fails, display widths, characters with combining marks |
| `src/buffer/` | Text with a line index, change sets, and a file's CRLF line ends, byte order mark and missing final newline |
| `src/regex/` | A linear-time, bounded regex engine (Pike VM) |
| `src/edit/` | Selections, motions, text objects, verbs, registers, search, undo |
| `src/input/` | Terminal bytes to keys, and the Kakoune-style keymap |
| `src/render/` | The cell grid, styles, and the diff into escape bytes |
| `src/ui/` | Gutter, text, status line, prompt, scrolling |
| `src/term/` | Raw mode, size, input waits, resizes, suspend, hang-ups and SIGTERM, restore on exit and panic |
| `src/fs/` | Bounded loads, atomic saves that keep permissions and links |
| `tests/` | Whole editing sessions from scripted keys, and the editor on a pseudo-terminal |
| `scripts/` | The files a dogfood pass edits ([`docs/dogfooding.md`](docs/dogfooding.md)) |

## Contributing

Read [`AGENTS.md`](AGENTS.md) first; it is the rulebook for humans and
coding agents alike. In short:

1. **Red:** write a test, run it, and watch it fail for the right reason.
2. **Green:** write the least code that passes.
3. **Refactor** with the suite green, then `zig build fmt` and run the tests
   in Debug and ReleaseSafe.
4. Open a pull request with a [Conventional Commit](https://www.conventionalcommits.org/)
   title and at least three lines of tests per line of code.

[`CONTRIBUTING.md`](CONTRIBUTING.md) walks through it step by step. Report
security problems privately, as [`SECURITY.md`](SECURITY.md) describes;
[`ACCESSIBILITY.md`](ACCESSIBILITY.md) says what works with assistive
technology today and what does not yet.

## License

[GNU Affero General Public License v3.0](LICENSE). mimalloc is MIT
licensed, © Microsoft Corporation.
