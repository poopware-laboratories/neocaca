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
/// Stores copies of `strings` in `name`. On error the register keeps
/// its old value.
pub fn set(self: *Registers, name: u8, strings: []const []const u8) error{OutOfMemory}!void {
    const copy = try self.gpa.alloc([]u8, strings.len);
    var n: usize = 0;
    errdefer {
        for (copy[0..n]) |s| self.gpa.free(s);
        self.gpa.free(copy);
    }
    while (n < strings.len) : (n += 1) copy[n] = try self.gpa.dupe(u8, strings[n]);
    self.free(self.values[name]);
    self.values[name] = copy;
}
```

(`src/edit/registers.zig`: everything that can fail runs before the old
value is touched, so a failure changes nothing.)

- Take the allocator as a parameter (name it `gpa` for long-lived memory,
  `arena` for scratch); store it in a struct only when the struct must free
  later, set in `init`.
- `defer` / `errdefer` on the line right after the acquisition.
- Doc comment on every function returning memory: owned by the caller, or
  borrowed and until when ("valid until the next edit of this buffer").
- `deinit(self: *T)` frees everything, then `self.* = undefined`.
- Standard containers are unmanaged: pass the allocator to each call
  (`list.append(gpa, x)`, `list.deinit(gpa)`) and keep it consistent.
- Scratch, when a frame or command needs it: an `ArenaAllocator`, reset
  with `.retain_capacity`. Nothing from the arena may outlive the reset.
- Sizes from files or the terminal are capped (`max_*`) before allocating.

## Which allocator

Library code never picks one: it uses the allocator it is given. `main.zig`
passes `std.heap.SafeAllocator` in Debug and the mimalloc wrapper
(`src/alloc/mimalloc.zig`) in release modes; tests always get
`std.testing.allocator`. A bug that shows only under mimalloc is still our
bug (usually a use after free or a wrong `free` length that the debug
allocator would report): reproduce it in Debug before blaming mimalloc.
Changing the wrapper: test alignment, resize, remap and huge requests in
Debug and ReleaseSafe, and benchmark against the previous version.

## Testing it

- Every test uses `std.testing.allocator`; a leak fails the test.
- Code that can fail to allocate gets an allocation-failure test, which
  fails each allocation in turn and checks nothing leaks:

  ```zig
  test "document: a failed allocation leaves the document as it was" {
      try std.testing.checkAllAllocationFailures(gpa, struct {
          fn run(a: std.mem.Allocator) !void {
              var doc: Document = try .init(a, "one two\n");
              defer doc.deinit();
              doc.edit(&.{.{ .start = 0, .end = 3, .text = "1" }}, &.{.at(0)}, 0) catch |err| {
                  try std.testing.expectEqualStrings("one two\n", doc.text());
                  try std.testing.expect(!doc.isModified());
                  return err;
              };
              try std.testing.expectEqualStrings("1 two\n", doc.text());
          }
      }.run, .{});
  }
  ```
  The `catch` checks the other half of the rule: an edit that fails to
  allocate leaves the document exactly as it was (see
  `src/edit/document_test.zig`).
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
