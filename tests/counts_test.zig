//! Counts typed before a key, as a person types them: moves, `f` and `x`
//! repeated on one selection and on thousands, which must answer at once.

const std = @import("std");
const Harness = @import("harness.zig").Harness;

const expectEqual = std.testing.expectEqual;

test "counts: 2w, 3l and 2f, move every selection" {
    var h: Harness = undefined;
    try h.init("t", "one two three four\nfive six seven eight\n", 40, 5);
    defer h.deinit();
    try h.typeKeys("C");
    try h.typeKeys("2w");
    try h.expectSelections(&.{ "two ", "six " });
    try h.typeKeys("3l");
    try h.expectSelections(&.{ "r", "v" });
    try h.typeKeys("2fe");
    try h.expectSelections(&.{ "ree", "ven e" });
}

test "counts: a million words on every word of a long file answers at once" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(std.testing.allocator);
    for (0..1000) |_| try text.appendSlice(std.testing.allocator, "word word word word word\n");
    var h: Harness = undefined;
    try h.init("t", text.items, 60, 5);
    defer h.deinit();
    try h.typeKeys("%S[ \\n]\r");
    try expectEqual(5000, h.session.ed.doc.sels().len);
    try h.typeKeys("1000000w");
    // Every selection walks to the end of the buffer, where they merge.
    try expectEqual(1, h.session.ed.doc.sels().len);
    try h.typeKeys("1000000b");
    try expectEqual(0, h.session.ed.doc.primary().cursor);
    try h.typeKeys("%S\\n\r");
    try h.typeKeys("1000000x");
    try h.expectSelections(&.{text.items});
}
