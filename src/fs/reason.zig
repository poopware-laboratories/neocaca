//! Why a file could not be read or written, in words for a message: the
//! errors `file.zig` and the system calls under it give on a POSIX system.

/// Words for `e`, lower case, to follow a colon. Errors no load or save
/// is known to give (Windows' own, misuse of a file) keep their name.
pub fn describe(e: anyerror) []const u8 {
    return switch (e) {
        error.AccessDenied, error.PermissionDenied => "permission denied",
        error.BadPathName => "the name is not valid",
        error.DeviceBusy, error.FileBusy => "the file is busy",
        error.DiskQuota => "the disk quota is used up",
        error.FileNotFound => "no such file or directory",
        error.FileTooBig, error.StreamTooLong => "the file is too big",
        error.InputOutput => "an input/output error",
        error.IsDir => "is a directory",
        error.NameTooLong => "the name is too long",
        error.NoSpaceLeft => "no space left on the device",
        error.NotAFile => "not a regular file",
        error.NotDir => "a part of the path is not a directory",
        error.OutOfMemory => "out of memory",
        error.PathAlreadyExists => "the file already exists",
        error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded => "too many open files",
        error.ReadOnly => "the file is read-only",
        error.ReadOnlyFileSystem => "the file system is read-only",
        error.SymLinkLoop => "too many symbolic links",
        error.SystemResources => "the system is out of resources",
        error.BrokenPipe => "the pipe is broken",
        error.Unexpected => "an unexpected error from the system",
        else => @errorName(e),
    };
}
