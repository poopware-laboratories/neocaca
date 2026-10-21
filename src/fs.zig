//! Files: `fs/file.zig` (bounded load, atomic save).

pub const file = @import("fs/file.zig");

pub const load = file.load;
pub const save = file.save;
pub const max_file = file.max_file;

test {
    _ = file;
    _ = @import("fs/file_test.zig");
}
