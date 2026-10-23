//! Tests for `reason.zig`: file errors in words.

const std = @import("std");
const reason = @import("reason.zig");

const expectEqualStrings = std.testing.expectEqualStrings;

test "reason: the errors people meet read as words" {
    try expectEqualStrings("is a directory", reason.describe(error.IsDir));
    try expectEqualStrings("no such file or directory", reason.describe(error.FileNotFound));
    try expectEqualStrings("permission denied", reason.describe(error.AccessDenied));
    try expectEqualStrings("permission denied", reason.describe(error.PermissionDenied));
    try expectEqualStrings("no space left on the device", reason.describe(error.NoSpaceLeft));
    try expectEqualStrings("the file system is read-only", reason.describe(error.ReadOnlyFileSystem));
    try expectEqualStrings("the file is read-only", reason.describe(error.ReadOnly));
    try expectEqualStrings("the file changed on disk", reason.describe(error.ChangedOnDisk));
    try expectEqualStrings("the file is too big", reason.describe(error.FileTooBig));
    try expectEqualStrings("not a regular file", reason.describe(error.NotAFile));
    try expectEqualStrings("a part of the path is not a directory", reason.describe(error.NotDir));
    try expectEqualStrings("too many symbolic links", reason.describe(error.SymLinkLoop));
}

test "reason: the rarer system errors read as words too" {
    try expectEqualStrings("the file is busy", reason.describe(error.FileBusy));
    try expectEqualStrings("the file is too big", reason.describe(error.StreamTooLong));
    try expectEqualStrings("too many open files", reason.describe(error.ProcessFdQuotaExceeded));
    try expectEqualStrings("an input/output error", reason.describe(error.InputOutput));
    try expectEqualStrings("the disk quota is used up", reason.describe(error.DiskQuota));
}

test "reason: an error from elsewhere keeps its name" {
    try expectEqualStrings("SomethingNew", reason.describe(error.SomethingNew));
    try expectEqualStrings("AntivirusInterference", reason.describe(error.AntivirusInterference));
}
