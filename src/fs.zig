//! Files: `fs/file.zig` (bounded load, atomic save, creating a new file),
//! `fs/link.zig` (the file a symbolic link names, for saves) and
//! `fs/reason.zig` (why one failed, in words).

pub const file = @import("fs/file.zig");

pub const load = file.load;
pub const save = file.save;
pub const create = file.create;
pub const max_file = file.max_file;
pub const describe = @import("fs/reason.zig").describe;

test {
    _ = file;
    _ = @import("fs/link.zig");
    _ = @import("fs/reason.zig");
    _ = @import("fs/file_test.zig");
    _ = @import("fs/reason_test.zig");
    _ = @import("fs/link_test.zig");
}
