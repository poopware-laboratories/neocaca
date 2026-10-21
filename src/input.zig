//! Input: terminal bytes to events (`input/decode.zig`, the pure parser,
//! and `input/decoder.zig`, which keeps bytes across reads and collects
//! pastes), the `Key` type (`input/key.zig`), and the modal keymap from
//! keys to editor actions (`input/keymap.zig`, `input/action.zig`).

pub const key = @import("input/key.zig");
pub const decode = @import("input/decode.zig");
pub const decoder = @import("input/decoder.zig");
pub const action = @import("input/action.zig");
pub const keymap = @import("input/keymap.zig");

pub const Key = key.Key;
pub const Decoder = decoder.Decoder;
pub const Event = decoder.Event;
pub const Action = action.Action;
pub const Keymap = keymap.Keymap;

test {
    _ = key;
    _ = decode;
    _ = decoder;
    _ = @import("input/decoder_test.zig");
    _ = action;
    _ = keymap;
    _ = @import("input/keymap_test.zig");
    _ = @import("input/decode_test.zig");
}
