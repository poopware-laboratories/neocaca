---
name: test-driven-development
description: Use before writing or changing any neocaca production code (a feature, a bug fix, a refactor), and when a test passed the first time it ran or the 3:1 test ratio is hard to meet.
---

# Test-driven development in neocaca

No production line is written before a test that fails without it. This is
not negotiable, including for "trivial" fixes.

## The loop

1. **Red: write the test first.** Put it next to the code it tests (a
   `test "…"` block at the end of the file, or the sibling `name_test.zig`).
   Name it as a sentence about behavior: `test "backspace at line start
   joins with the previous line"`.
2. **Run only it** and read the failure:
   ```sh
   zig build test -Dtest-filter="backspace at line start" --summary all
   ```
   It must fail for the expected reason: an `expect*` mismatch, or a
   compile error naming the function you have not written yet. A leak
   report, a typo or a crash in setup means the test is wrong; fix it and
   run again until it is red for the right reason.
3. **Green: the least code that passes.** Hard-code if the test allows
   it; the next test forces the generalization. No options, parameters or
   branches no test demands.
4. **Refactor** with `zig build test` green after every step.
5. **Repeat** with the next behavior: the next edge case is the next red.

For a bug: the first commit can be the regression test alone, built from
the exact input of the report.

## Shape of a good test

Bytes or plain data in, state or bytes out, with the leak-checking
allocator:

```zig
test "backspace at line start joins with the previous line" {
    var buf = try Buffer.initText(std.testing.allocator, "ab\ncd");
    defer buf.deinit();
    var cursor: Cursor = .{ .line = 1, .col = 0 };

    try edit.backspace(&buf, &cursor);

    try std.testing.expectEqualStrings("abcd", try buf.lineSlice(0));
    try std.testing.expectEqual(Cursor{ .line = 0, .col = 2 }, cursor);
}
```

Prefer `expectEqualStrings` / `expectEqualSlices` (they print a diff) over
`expect(a == b)`. Integration tests in `tests/` feed scripted input bytes
to a whole editor and assert on the final `Screen` text and buffers.

## What to cover

1. **Edges and bounds:** empty buffer, one character, first and last line
   and column, end of file with and without a final newline, `max_*`
   limits and one past them.
2. **Text that is not ASCII:** multi-byte UTF-8, wide (CJK, emoji) and
   combining characters, tabs, CRLF, invalid UTF-8, NUL and control bytes.
3. **Failure paths:** every error the function returns, and allocation
   failure via `std.testing.checkAllAllocationFailures` (see
   managing-memory). After an error, state is unchanged.
4. **Undo:** every edit command undoes to the exact previous buffer and
   cursor, and redoes back.
5. **Differential cases:** a fast path against the simple version it
   replaces, on random inputs from a seeded `std.Random.DefaultPrng` (print
   the seed on failure so it reproduces), plus handwritten edges.

## Seen to fail, or it proves nothing

A test that passed on its first run has not been seen to fail. For it, and
for characterization tests of existing code: break the production code on
purpose (flip a comparison, drop a branch, shift a bound by one), run the
test, watch it fail, restore. A mutant no test catches is a missing test,
or code with no observable effect that should be deleted.

## Red flags

- "I'll write the tests after it works."
- Production code in the diff before any test changed.
- A test asserting what the compiler already guarantees, or a constant.
- Repeating one assertion with different names to reach 3:1.
- A test that still passes when the new code is reverted.

Any of these means: stop, delete the untested code or the padding, and go
back to step 1.
