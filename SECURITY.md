# Security policy

An editor opens files it did not write, inside a terminal that obeys
escape sequences. neocaca treats both as hostile. This page says what we
protect against, what the limits are, and how to tell us when something
gets through.

## Reporting a vulnerability

**Do not open a public issue for a security problem.** Report it
privately through GitHub:
[**Report a vulnerability**](https://github.com/poopware-laboratories/neocaca/security/advisories/new)
(the *Security* tab, then *Report a vulnerability*).

If that form is not available to you, open an issue that only asks for a
private contact, with no details of the problem.

A useful report includes:

- what an attacker controls (a file's contents, its name, a symbolic
  link, bytes the terminal sends back) and what they gain;
- the smallest file or key sequence that shows it, and the commit you
  tested (`git rev-parse HEAD`);
- your operating system, terminal emulator and build mode
  (`-Doptimize=safe` is the build we ship).

We will acknowledge the report, work on a fix in a private advisory, and
credit you when the fix is published unless you ask us not to. Please give
us a reasonable time to ship the fix before you disclose the problem.

## Supported versions

neocaca has no releases yet. Fixes go to `main` only. Once releases exist,
this section will list which ones receive security fixes.

## What we treat as untrusted

| Input | What could go wrong | How neocaca handles it |
|-------|---------------------|------------------------|
| File contents | Escape sequences that retitle, recolor or reprogram the terminal; invalid UTF-8; NUL bytes; huge lines and files | Control bytes are drawn as visible text (`^[`), never written raw; UTF-8 decoding never fails and shows bad bytes as U+FFFD; loads are capped at 256 MiB (`fs.max_file`) |
| Special files | A named pipe that never answers, a device that never ends (`/dev/zero`) | Only regular files are loaded; anything else is refused with `NotAFile` |
| Paths and links | A save that replaces a symbolic link, or a recovery file that overwrites something | Saves follow links (at most 40) and replace the file they name; recovery files are created only where nothing exists |
| Saving | A crash, a full disk or the file size limit truncating the file | Saves write a temporary file in the same directory, created anew and never an existing one, and rename it over the original, keeping its permissions; on any error the original is untouched, and a write past the file size limit (`SIGXFSZ`, which the editor ignores) is such an error. A file that another program changed since it was read, or one with other hard links (which would keep the old text), is not written over without `:w!` |
| Terminal input | Malformed or endless control sequences, huge pastes | Sequences are bounded (`max_csi`) and longer ones skipped whole, never typed; pastes are capped at 16 MiB; nothing the terminal sends is echoed back to it |
| Search patterns | Patterns that take exponential time or unbounded memory | The regex engine runs in linear time (a Pike VM) with limits on pattern length, nesting, repetition counts and program size; one search or `s`, `S`, `Alt-k` command takes at most 2^28 steps (`regex.max_steps`), then stops with a message and changes nothing |
| Terminal size | A terminal that reports an enormous size, exhausting memory on every frame | Screens hold at most 4096 columns or rows and 1,048,576 cells (`max_side`, `max_cells`); a larger terminal is drawn in its top left corner |
| Selections | A command that makes one selection per match or line, millions of them, freezing the editor and exhausting memory | A document holds at most 1,048,576 selections (`max_selections`); `s`, `S`, `Alt-s`, `C` and `N` that would make more stop as they pass it, say so and change nothing |
| Counts and prompts | A count or prompt large enough to freeze or exhaust memory | Counts stop at 1,000,000, prompts at 4096 bytes, and `:map` at 256 mappings of at most 32 keys each; a counted move or `x` costs about the length of the text, however many selections there are |

Every limit is a named `max_*` constant, tested at the limit and one past
it.

## How it is built to resist

- **Safety checks stay on.** The shipped build is ReleaseSafe: bounds,
  integer overflow and unreachable-code checks remain on, so a bug stops
  the editor instead of corrupting memory. Fast paths are written so those
  checks cost nothing; they are not turned off.
- **A hardened allocator.** Release builds use mimalloc with its secure
  mode on (guard pages, randomized allocation, double-free and free-list
  corruption detection). Debug builds and tests use Zig's leak-checking
  allocator.
- **Out of memory is an error, not a crash.** An edit that cannot allocate
  leaves the buffer as it was; the code that handles allocation failure is
  tested by failing each of its allocations in turn.
- **The terminal is always restored**, on a normal exit, on an error and on
  a panic. When the terminal hangs up, or the editor is told to end
  (SIGTERM), with changes unsaved, they go to a `<file>.recovered` file
  instead of being lost (a name too long for the suffix is cut to fit);
  when even that fails, the editor says so and exits with status 1.
- **One dependency.** Apart from the Zig standard library, the only
  third-party code is mimalloc, pinned by URL and hash in `build.zig.zon`.

## Out of scope

- Anything that needs an attacker to run code as your user already, or to
  change your build environment.
- Bugs in your terminal emulator, unless neocaca sends it something that
  came from a file.
- Debug builds' crashes on assertions: those are bugs we want to hear
  about, through an ordinary issue, unless they lead somewhere worse.
