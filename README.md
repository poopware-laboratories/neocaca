<div align="center">

# neocaca

**A modern terminal code editor, written in Zig.**
Fast where it counts, careful everywhere else.

[![CI](https://github.com/poopware-laboratories/neocaca/actions/workflows/ci.yml/badge.svg)](https://github.com/poopware-laboratories/neocaca/actions/workflows/ci.yml)
[![Zig 0.17.0](https://img.shields.io/badge/zig-0.17.0-f7a41d?logo=zig&logoColor=white)](https://ziglang.org/download/)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

</div>

> [!WARNING]
> **Early days.** The foundations are in (build, allocator, SIMD text
> scanning, command line), but there is no editing yet: `neocaca file`
> says so and exits. Watch the [issues](https://github.com/poopware-laboratories/neocaca/issues)
> to follow along, or pick one up.

## What it is built for

These are the rules every part of neocaca is held to, from the first
line of code:

- **Your files are safe.** Saves are atomic, every edit can be undone, and
  a crash never truncates a file.
- **Opening a file can't attack your terminal.** File contents are treated
  as untrusted: escape sequences and control bytes are shown visibly, never
  written to the terminal raw. (The SIMD scan that finds them is already
  in.)
- **Fast on big files.** Text scanning uses SIMD, and the release
  allocator is [mimalloc](https://github.com/microsoft/mimalloc).
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
| Rendering (planned) | Only changed cells are redrawn | Control bytes from files are made visible, never sent to the terminal |

Scanning 64 MiB of text, in ReleaseSafe, with the hardened mimalloc
(`zig build bench -Dbench-optimize=safe`, x86-64 with AVX2, one noisy
cloud machine):

| Kernel | Scalar | SIMD |
|--------|-------:|-----:|
| Count newlines | 2.2 GiB/s | 20.9 GiB/s |
| Find a byte | 4.6 GiB/s | 22.3 GiB/s |
| Find a control byte | 2.2 GiB/s | 26.7 GiB/s |

ReleaseFast runs at about the same speed: the kernels' loops let the
compiler prove their bounds checks redundant, so it removes them itself.

## Getting started

You need [Zig 0.17.0](https://ziglang.org/download/). mimalloc is fetched
and built from source by `zig build`; no CMake or system packages needed.

```sh
git clone https://github.com/poopware-laboratories/neocaca
cd neocaca
zig build -Doptimize=safe          # zig-out/bin/neocaca
./zig-out/bin/neocaca --help
```

| Command | What it does |
|---------|--------------|
| `zig build` | Debug build, with the leak-checking allocator |
| `zig build -Doptimize=safe` | The shipping build |
| `zig build test --summary all` | Every test |
| `zig build test -Dtest-filter="name"` | Only matching tests |
| `zig build test -fincremental --watch` | Rerun the tests on every save, incrementally (x86_64-linux) |
| `zig build fmt` | Format the sources (`fmt-check` to only check) |
| `zig build bench` | SIMD against scalar throughput |
| `zig build -Dtarget=aarch64-macos` | Cross-compile (Linux, macOS, FreeBSD) |
| `-Dmimalloc-secure=off\|on\|full` | mimalloc hardening level (default `on`) |

## How it is built

```
stdin ──► input::decode ──► app::EventLoop ──► edit::Command ──► buffer::Buffer
                                 │                                   │
terminal ◄── render::diff ◄── render::Screen ◄── ui::layout ◄────────┘
```

A pure core (buffers, editing, input decoding, layout, screen diffing)
that tests run without a terminal, behind a thin layer that does the I/O.
The full layout is in [`AGENTS.md`](AGENTS.md#architecture-in-one-screen).

| Path | Status |
|------|--------|
| `src/alloc/` | mimalloc as a `std.mem.Allocator`; per-mode allocator choice |
| `src/simd/` | Byte counting, byte search, control-byte search |
| `src/cli.zig`, `src/main.zig` | Command line and process setup |
| `src/buffer/`, `src/edit/`, `src/input/`, `src/render/`, `src/ui/`, `src/term/`, `src/fs/` | Planned |

## Contributing

Read [`AGENTS.md`](AGENTS.md) first; it is the rulebook for humans and
coding agents alike. In short:

1. **Red:** write a test, run it, and watch it fail for the right reason.
2. **Green:** write the least code that passes.
3. **Refactor** with the suite green, then `zig build fmt` and run the tests
   in Debug and ReleaseSafe.
4. Open a pull request with a [Conventional Commit](https://www.conventionalcommits.org/)
   title and at least three lines of tests per line of code.

## License

[GNU Affero General Public License v3.0](LICENSE). mimalloc is MIT
licensed, © Microsoft Corporation.
