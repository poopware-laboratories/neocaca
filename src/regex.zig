//! Regular expressions for search, select and split: parsing (`regex/parse.zig`
//! into `regex/ast.zig`), compiling (`regex/program.zig`) and a Pike VM
//! (`regex/vm.zig`) that matches in linear time over any bytes. Syntax:
//! literals, `.`, `[...]` classes with ranges and `^`, `\d \w \s` and their
//! negations, `* + ?` and `{n} {n,} {n,m}` (lazy with a trailing `?`), `|`,
//! `(...)` and `(?:...)`, `^ $` (line start and end), `\b \B`, and `\n \t \r`.

const regex = @import("regex/regex.zig");

pub const Regex = regex.Regex;
pub const Match = regex.Match;
pub const Error = regex.Error;
pub const escape = regex.escape;
pub const parse = @import("regex/parse.zig");

test {
    _ = regex;
    _ = parse;
    _ = @import("regex/program.zig");
    _ = @import("regex/vm.zig");
    _ = @import("regex/regex_test.zig");
    _ = @import("regex/parse_test.zig");
}
