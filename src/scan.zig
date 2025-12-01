const std = @import("std");

const ascii = std.ascii;
const io = std.io;
const math = std.math;
const mem = std.mem;

const Reader = std.io.Reader;

const Error = error{
    NoMatch,
};

/// Try and read `expect` from the front of `r`.
///
/// If `r` starts with `expect`, the bytes are consumed, otherwise an error is
/// returned, and `r` is left unchanged.
///
/// Can also produce an error if `r`'s buffer is not big enough to hold `expect`.
pub fn prefix(r: *Reader, expect: []const u8) !void {
    const actual = r.peek(expect.len) catch return error.NoMatch;
    if (mem.eql(u8, actual, expect)) {
        r.toss(expect.len);
    } else {
        return error.NoMatch;
    }
}

/// Try and read an unsigned decimal number from the front of `r`.
///
/// If `r` starts with an unsigned decimal number, reads, parses, and returns
/// it. Otherwise `r` is left unchanged.
pub fn unsigned(comptime T: type, r: *Reader) !T {
    var result: T = @intCast(try decimalDigit(r));

    while (decimalDigit(r) catch null) |digit| {
        result = try math.mul(T, result, 10);
        result = try math.add(T, result, @intCast(digit));
    }

    return result;
}

/// Try and read a single decimal digit from the front of `r`.
///
/// If `r` starts with a decimal digit ('0'..'9'), consumes and returns it.
/// Otherwise `r` is left unchanged and `error.NoMatch` is returned.
pub fn decimalDigit(r: *Reader) !u8 {
    const byte = r.peek(1) catch return error.NoMatch;
    if (!ascii.isDigit(byte[0])) {
        return error.NoMatch;
    }

    r.toss(1);
    return byte[0] - '0';
}

/// Try and read an enum from the front of `r`.
///
/// Assumes that `E` is a simple enum (just variants, no associated values).
/// Checks whether the front of `r` matches the enum variant names, and if so,
/// returns the first one that matches, consuming it from the front of `r`.
///
/// If none match, returns an error, leaving `r` unchanged.
pub fn @"enum"(comptime E: type, r: *Reader) !E {
    const info = @typeInfo(E);

    const enum_ = switch (info) {
        .@"enum" => |e| e,
        else => @compileError("scanEnum can only be used with enums"),
    };

    inline for (enum_.fields) |field| {
        const name = field.name;
        if (prefix(r, name)) {
            return @enumFromInt(field.value);
        } else |_| {}
    }

    return error.NoMatch;
}

test "prefix" {
    var r = Reader.fixed("hello world");
    try std.testing.expectError(error.NoMatch, prefix(&r, "goodbye"));
    try prefix(&r, "hello");
    try prefix(&r, " world");
    try std.testing.expectError(error.NoMatch, prefix(&r, "no more"));
}

test "decimalDigit" {
    var r = Reader.fixed("123abc");
    try std.testing.expectEqual(1, try decimalDigit(&r));
    try std.testing.expectEqual(2, try decimalDigit(&r));
    try std.testing.expectEqual(3, try decimalDigit(&r));
    try std.testing.expectError(error.NoMatch, decimalDigit(&r));
    try prefix(&r, "abc");
}

test "unsigned" {
    var r = Reader.fixed("4567xyz");
    try std.testing.expectEqual(4567, try unsigned(u32, &r));
    try std.testing.expectError(error.NoMatch, unsigned(u32, &r));
    try prefix(&r, "xyz");
}

test "enum" {
    const Color = enum {
        red,
        green,
        blue,
    };

    var r = Reader.fixed("greenblueredturquoise");
    try std.testing.expectEqual(Color.green, try @"enum"(Color, &r));
    try std.testing.expectEqual(Color.blue, try @"enum"(Color, &r));
    try std.testing.expectEqual(Color.red, try @"enum"(Color, &r));
    try std.testing.expectError(error.NoMatch, @"enum"(Color, &r));
    try prefix(&r, "turquoise");
}
