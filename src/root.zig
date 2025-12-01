const std = @import("std");

pub const grid = @import("./grid.zig");
pub const scan = @import("./scan.zig");

const Limit = std.Io.Limit;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

test {
    // This is necessary for the test build to pick up all tests in imported/re-exported modules.
    @import("std").testing.refAllDeclsRecursive(@This());
}

/// Read a line including its delimiter from `Reader` `r`, as long as it fits
/// into the reader's internal buffer.
///
/// Returns `null` if there are no more line separators.
pub fn readLineInclusive(r: *Reader) !?[]u8 {
    return r.takeDelimiterInclusive('\n') catch |e| switch (e) {
        error.EndOfStream => return null,
        else => return e,
    };
}

/// Read a line without its delimiter from `Reader`, `r`, as long as it fits
/// into the reader's internal buffer.
///
/// Returns `null` if there are no more non-empty lines.
pub fn readLineExclusive(r: *Reader) !?[]u8 {
    const line = r.takeDelimiterExclusive('\n') catch |e| switch (e) {
        error.EndOfStream => return null,
        else => return e,
    };

    _ = r.discard(.limited(1)) catch {};
    return line;
}

test "readLineInclusive simple" {
    var r = Reader.fixed("hello\nworld\n");
    try std.testing.expectEqualStrings("hello\n", (try readLineInclusive(&r)).?);
    try std.testing.expectEqualStrings("world\n", (try readLineInclusive(&r)).?);
    try std.testing.expectEqual(null, try readLineInclusive(&r));
}

test "readLineInclusive no delimiter" {
    var r = Reader.fixed("hello");
    try std.testing.expectEqual(null, try readLineInclusive(&r));
}

test "readLineExclusive simple" {
    var r = Reader.fixed("hello\nworld\n");
    try std.testing.expectEqualStrings("hello", (try readLineExclusive(&r)).?);
    try std.testing.expectEqualStrings("world", (try readLineExclusive(&r)).?);
    try std.testing.expectEqual(null, try readLineExclusive(&r));
}

test "readLineExclusive no delimiter" {
    var r = Reader.fixed("hello");
    try std.testing.expectEqualStrings("hello", (try readLineExclusive(&r)).?);
}
