const std = @import("std");
const lib = @import("root.zig");

const math = std.math;

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const Reader = std.io.Reader;

pub const Point = struct {
    x: usize,
    y: usize,

    // Construct a new `Point`.
    pub fn pt(x: usize, y: usize) Point {
        return .{ .x = x, .y = y };
    }

    /// Returns a new point moved in the given direction by the given steps.
    pub fn move(self: Point, dx: isize, dy: isize) ?Point {
        return .{
            .x = if (dx < 0)
                math.sub(usize, self.x, @intCast(-dx)) catch return null
            else
                math.add(usize, self.x, @intCast(dx)) catch return null,

            .y = if (dy < 0)
                math.sub(usize, self.y, @intCast(-dy)) catch return null
            else
                math.add(usize, self.y, @intCast(dy)) catch return null,
        };
    }
};

pub const Error = error{
    Dimensions,
    OutOfBounds,
};

fn FindIter(comptime T: type) type {
    return struct {
        grid: Grid(T),
        elem: T,
        idx: usize,

        const Self = @This();

        pub fn next(self: *Self) ?Point {
            while (self.idx < self.grid.items.len) {
                const idx = self.idx;
                self.idx += 1;

                const item = self.grid.items[idx];
                if (item == self.elem) {
                    const x = idx % self.grid.width;
                    const y = idx / self.grid.width;
                    return .pt(x, y);
                }
            } else {
                return null;
            }
        }
    };
}

fn RowIter(comptime T: type) type {
    return struct {
        grid: Grid(T),
        lo: usize,

        const Self = @This();

        pub fn next(self: *Self) ?[]T {
            if (self.lo >= self.grid.items.len) {
                return null;
            }

            const hi = self.lo + self.grid.width;
            const row = self.grid.items[self.lo..hi];
            self.lo = hi;
            return row;
        }
    };
}

/// A 2D grid of items of type `T`.
pub fn Grid(comptime T: type) type {
    return struct {
        width: usize,
        height: usize,
        items: []T,

        const Self = @This();

        /// An empty grid
        pub const empty = Self{
            .width = 0,
            .height = 0,
            .items = &[_]T{},
        };

        /// Initialize a grid of width `width` from the given `items`, taking
        /// control of `items`.
        ///
        /// Fails if `items` can't be evenly divided into rows of `width`.
        pub fn init(width: usize, items: []T) !Self {
            if (items.len % width != 0) {
                return Error.Dimensions;
            }

            return Self{
                .width = width,
                .height = items.len / width,
                .items = items,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }

        /// Get the item at position `pt`, or `null` if out of bounds.
        pub fn get(self: Self, pt: Point) ?T {
            if (pt.x < self.width and pt.y < self.height) {
                return self.items[pt.y * self.width + pt.x];
            } else {
                return null;
            }
        }

        /// Get a pointer to the item at position `(x, y)`, or `null` if out of bounds.
        pub fn getPtr(self: *Self, x: usize, y: usize) ?*T {
            if (x < self.width and y < self.height) {
                return &self.items[y * self.width + x];
            } else {
                return null;
            }
        }

        /// Assign `value` at position `pt`, discarding/overwriting the
        /// previous value.
        pub fn put(self: *Self, pt: Point, value: T) !void {
            if (pt.x >= self.width or pt.y >= self.height) {
                return Error.OutOfBounds;
            }

            self.items[pt.y * self.width + pt.x] = value;
        }

        /// Find all occurrences of `elem` in the grid.
        ///
        /// Returns an iterator over the points where `elem` is found.
        pub fn find(self: Self, elem: T) FindIter(T) {
            return FindIter(T){
                .grid = self,
                .elem = elem,
                .idx = 0,
            };
        }

        /// Iterate over each row of the grid.
        ///
        /// Rows are returned as slices of `T`.
        pub fn rows(self: Self) RowIter(T) {
            return RowIter(T){
                .grid = self,
                .lo = 0,
            };
        }

        /// Get the row at index `y`, or `null` if out of bounds.
        pub fn row(self: Self, y: usize) ?[]T {
            if (y >= self.height) {
                return null;
            }

            const start = y * self.width;
            return self.items[start .. start + self.width];
        }
    };
}

/// Reads a grid of bytes from `r`, where each line represents a row in the grid.
pub fn read(r: *Reader, a: Allocator) !Grid(u8) {
    var items = ArrayList(u8).init(a);
    defer items.deinit();

    const first = try lib.readLineExclusive(r) orelse return Grid(u8).empty;
    if (first.len <= 1) {
        return Grid(u8).empty;
    }

    const width = first.len;
    try items.appendSlice(first);

    while (try lib.readLineExclusive(r)) |line| {
        if (line.len <= 1) break;
        if (line.len != width) {
            return Error.Dimensions;
        }

        try items.appendSlice(line);
    }

    return try Grid(u8).init(width, try items.toOwnedSlice());
}

test "Point.move" {
    const p: Point = .pt(2, 2);

    try std.testing.expectEqual(p.move(-1, -1).?, Point.pt(1, 1));
    try std.testing.expectEqual(p.move(2, 1).?, Point.pt(4, 3));
    try std.testing.expectEqual(p.move(-2, -2).?, Point.pt(0, 0));
    try std.testing.expectEqual(p.move(2, 2).?, Point.pt(4, 4));
    try std.testing.expectEqual(p.move(-3, 0), null);
    try std.testing.expectEqual(p.move(0, -3), null);
}

test "read" {
    var r = Reader.fixed(
        \\123
        \\456
    );

    var grid = try read(&r, std.testing.allocator);
    defer grid.deinit(std.testing.allocator);

    try std.testing.expectEqual(3, grid.width);
    try std.testing.expectEqual(2, grid.height);
    try std.testing.expectEqual('1', grid.get(.pt(0, 0)).?);
    try std.testing.expectEqual('2', grid.get(.pt(1, 0)).?);
    try std.testing.expectEqual('3', grid.get(.pt(2, 0)).?);
    try std.testing.expectEqual('4', grid.get(.pt(0, 1)).?);
    try std.testing.expectEqual('5', grid.get(.pt(1, 1)).?);
    try std.testing.expectEqual('6', grid.get(.pt(2, 1)).?);
}

test "empty" {
    var r = Reader.fixed("");

    var grid = try read(&r, std.testing.allocator);
    defer grid.deinit(std.testing.allocator);

    try std.testing.expectEqual(0, grid.width);
    try std.testing.expectEqual(0, grid.height);
}

test "read inconsistent dimensions" {
    var r = Reader.fixed(
        \\123
        \\45
    );

    const result = read(&r, std.testing.allocator);
    try std.testing.expectError(Error.Dimensions, result);
}

test "init inconsistent dimensions" {
    var items = [_]u8{ 1, 2, 3, 4, 5 };
    const result = Grid(u8).init(3, items[0..]);
    try std.testing.expectError(Error.Dimensions, result);
}

test "read multiple" {
    var r = Reader.fixed(
        \\12
        \\34
        \\
        \\56
        \\78
    );

    var fst = try read(&r, std.testing.allocator);
    defer fst.deinit(std.testing.allocator);

    try std.testing.expectEqual(2, fst.width);
    try std.testing.expectEqual(2, fst.height);
    try std.testing.expectEqual('1', fst.get(.pt(0, 0)).?);
    try std.testing.expectEqual('2', fst.get(.pt(1, 0)).?);
    try std.testing.expectEqual('3', fst.get(.pt(0, 1)).?);
    try std.testing.expectEqual('4', fst.get(.pt(1, 1)).?);

    var snd = try read(&r, std.testing.allocator);
    defer snd.deinit(std.testing.allocator);

    try std.testing.expectEqual(2, snd.width);
    try std.testing.expectEqual(2, snd.height);
    try std.testing.expectEqual('5', snd.get(.pt(0, 0)).?);
    try std.testing.expectEqual('6', snd.get(.pt(1, 0)).?);
    try std.testing.expectEqual('7', snd.get(.pt(0, 1)).?);
    try std.testing.expectEqual('8', snd.get(.pt(1, 1)).?);
}

test "put and get" {
    var r = Reader.fixed(
        \\12
        \\34
    );

    var grid = try read(&r, std.testing.allocator);
    defer grid.deinit(std.testing.allocator);

    try std.testing.expectEqual('1', grid.get(.pt(0, 0)).?);
    try grid.put(.pt(0, 0), 'A');
    try std.testing.expectEqual('A', grid.get(.pt(0, 0)).?);
}

test "find" {
    var r = Reader.fixed(
        \\121
        \\232
        \\121
    );

    var grid = try read(&r, std.testing.allocator);
    defer grid.deinit(std.testing.allocator);

    var iter = grid.find('2');
    const p0 = iter.next().?;
    try std.testing.expectEqual(Point.pt(1, 0), p0);

    const p1 = iter.next().?;
    try std.testing.expectEqual(Point.pt(0, 1), p1);

    const p2 = iter.next().?;
    try std.testing.expectEqual(Point.pt(2, 1), p2);

    const p3 = iter.next().?;
    try std.testing.expectEqual(Point.pt(1, 2), p3);

    const end = iter.next();
    try std.testing.expectEqual(null, end);
}

test "rows" {
    var r = Reader.fixed(
        \\1234
        \\5678
    );

    var grid = try read(&r, std.testing.allocator);
    defer grid.deinit(std.testing.allocator);

    var iter = grid.rows();
    const r0 = iter.next().?;
    try std.testing.expectEqualStrings("1234", r0);

    const r1 = iter.next().?;
    try std.testing.expectEqualStrings("5678", r1);

    const end = iter.next();
    try std.testing.expectEqual(null, end);
}

test "row" {
    var r = Reader.fixed(
        \\abcd
        \\efgh
    );

    var grid = try read(&r, std.testing.allocator);
    defer grid.deinit(std.testing.allocator);

    const r0 = grid.row(0).?;
    try std.testing.expectEqualStrings("abcd", r0);

    const r1 = grid.row(1).?;
    try std.testing.expectEqualStrings("efgh", r1);

    const r2 = grid.row(2);
    try std.testing.expectEqual(null, r2);
}
