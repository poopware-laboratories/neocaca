---
name: managing-memory
description: Use when writing or reviewing neocaca code that allocates, frees, stores an allocator, returns owned or borrowed slices, uses arenas, or when a test reports a leak, double free or use after free.
---

# Managing memory in neocaca

Every allocation is explicit, owned by someone, and freed on every path,
error paths included. The rules are in AGENTS.md ("Memory and
allocators"); this is how to apply and test them.

## Writing it

```zig
/// Returns the text of `range`. Caller owns the returned slice.
pub fn copyRange(self: *const Buffer, gpa: std.mem.Allocator, range: Range) ![]u8 {
    const out = try gpa.alloc(u8, range.len());
    errdefer gpa.free(out);
    try self.readInto(range, out);
    return out;
}
```

- Take the allocator as a parameter (name it `gpa` for long-lived memory,
  `arena` for scratch); store it in a struct only when the struct must free
  later, set in `init`.
- `defer` / `errdefer` on the line right after the acquisition.
- Doc comment on every function returning memory: owned by the caller, or
  borrowed and until when ("valid until the next edit of this buffer").
- `deinit(self: *T)` frees everything, then `self.* = undefined`.
- Standard containers are unmanaged: pass the allocator to each call
  (`list.append(gpa, x)`, `list.deinit(gpa)`) and keep it consistent.
- Scratch per frame or command: an `ArenaAllocator`, reset with
  `.retain_capacity`. Nothing from the arena may outlive the reset.
- Sizes from files or the terminal are capped (`max_*`) before allocating.

## Testing it

- Every test uses `std.testing.allocator`; a leak fails the test.
- Code that can fail to allocate gets an allocation-failure test, which
  fails each allocation in turn and checks nothing leaks:

  ```zig
  fn insertThenUndo(gpa: std.mem.Allocator) !void {
      var buf = try Buffer.initText(gpa, "hello");
      defer buf.deinit();
      try buf.insert(5, " world");
      try buf.undo();
      try std.testing.expectEqualStrings("hello", try buf.lineSlice(0));
  }

  test "insert and undo survive every allocation failure" {
      try std.testing.checkAllAllocationFailures(std.testing.allocator, insertThenUndo, .{});
  }
  ```
- For "an edit that fails leaves the buffer unchanged", use
  `std.testing.FailingAllocator` with a fail index and compare the buffer
  before and after the failed call.
- Run the suite in Debug and ReleaseSafe: both keep safety checks; a
  segfault or "use of undefined" only in one mode is still a bug.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| `errdefer` missing between `alloc` and a later `try` | Add it right after the alloc. |
| Returning a slice into an arena that resets this frame | Copy it with `gpa`, or document and shorten its lifetime. |
| Keeping a slice into an `ArrayList` across an append | Appends reallocate; store indices, not slices. |
| `catch unreachable` / `@panic` on `error.OutOfMemory` | Propagate it. |
| A global or `std.heap.page_allocator` in library code | Take an allocator parameter. |
| Freeing with a different allocator than allocated | Keep one allocator per owner; tests catch it. |
