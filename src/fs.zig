//! Files: `fs/file.zig` (bounded load, atomic save, creating a new file),
//! `fs/temp.zig` (the temporary file a save writes), `fs/disk.zig`
//! (what a file was on disk, so a save can tell it changed), `fs/link.zig` (the
//! file a symbolic link names, for saves), `fs/owner.zig` (a file's owner
//! and group, which a save keeps) and `fs/reason.zig` (why one failed, in
//! words).

pub const file = @import("fs/file.zig");
pub const disk = @import("fs/disk.zig");

pub const load = file.load;
pub const save = file.save;
pub const create = file.create;
pub const max_name = file.max_name;
pub const fitName = file.fitName;
pub const max_file = file.max_file;
pub const describe = @import("fs/reason.zig").describe;

test {
    _ = file;
    _ = disk;
    _ = @import("fs/link.zig");
    _ = @import("fs/temp.zig");
    _ = @import("fs/reason.zig");
    _ = @import("fs/file_test.zig");
    _ = @import("fs/file_dir_test.zig");
    _ = @import("fs/reason_test.zig");
    _ = @import("fs/link_test.zig");
    _ = @import("fs/temp_test.zig");
    _ = @import("fs/disk_test.zig");
    _ = @import("fs/owner.zig");
    _ = @import("fs/owner_test.zig");
}
