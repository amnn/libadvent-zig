const std = @import("std");

const math = std.math;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

data: ?[]i64 = null,
rows: [][*]i64,
cols: usize,

const Self = @This();

/// Initialize a new matrix with width `cols`, from the provided `data`.
///
/// `cols` must divide evenly into the length of `data`, otherwise an error is
/// returned.
///
/// This function does not take ownership of `data` -- it remains the caller's
/// responsibility to clean it up.
pub fn new(a: Allocator, cols: usize, data: []i64) !Self {
    const rows = try a.alloc([*]i64, math.divExact(usize, data.len, cols) catch {
        return error.InvalidMatrixSize;
    });

    errdefer a.free(rows);
    for (rows, 0..) |*r, i| {
        r.* = data.ptr + i * cols;
    }

    return .{ .cols = cols, .rows = rows };
}

/// Constructs a `cols` by `rows` matrix filled with zeros.
pub fn zero(a: Allocator, cols: usize, rows: usize) !Self {
    const size = cols * rows;
    const data = try a.alloc(i64, size);
    errdefer a.free(data);

    for (data) |*d| d.* = 0;
    var m: Self = try .new(a, cols, data);
    errdefer m.deinit(a);

    m.data = data;
    return m;
}

/// Constructs a `size` by `size` square identity matrix.
pub fn identity(a: Allocator, size: usize) !Self {
    const data = try a.alloc(i64, size * size);
    errdefer a.free(data);

    for (data) |*d| d.* = 0;
    for (0..size) |i| {
        data[i * size + i] = 1;
    }

    var m: Self = try .new(a, size, data);
    errdefer m.deinit(a);

    m.data = data;
    return m;
}

/// Clean up the data allocated for this matrix.
pub fn deinit(self: *Self, a: Allocator) void {
    if (self.data) |d| a.free(d);
    a.free(self.rows);
}

pub fn width(self: *const Self) usize {
    return self.cols;
}

pub fn height(self: *const Self) usize {
    return self.rows.len;
}

/// Get a copy of the value at cell `(c, r)`.
pub fn get(self: *const Self, c: usize, r: usize) ?i64 {
    const row_ = self.row(r) orelse return null;
    return if (c < self.cols) row_[c] else null;
}

/// Mutable access to the cell at `(c, r)`.
pub fn ptr(self: *Self, c: usize, r: usize) ?*i64 {
    const row_ = self.rowPtr(r) orelse return null;
    return if (c < self.cols) &row_[c] else null;
}

/// Read-only access to the contents of row `r`.
pub fn row(self: *const Self, r: usize) ?[]const i64 {
    return if (r < self.rows.len)
        self.rows[r][0..self.cols]
    else
        null;
}

/// Mutable access to the contents of row `r`.
pub fn rowPtr(self: *Self, r: usize) ?[]i64 {
    return if (r < self.rows.len)
        self.rows[r][0..self.cols]
    else
        null;
}

/// Return a new Matrix by slicing rows out of this Matrix.
///
/// All modifications to this slice are propagated to the original matrix, and
/// vice versa, as they share an underlying data buffer.
///
/// Fails if the range to slice is invalid (out of bounds or degenerate).
pub fn slice(self: *const Self, from: usize, to: usize) ?Self {
    if (to > self.rows.len or from > to) {
        return null;
    }

    return .{
        .data = null,
        .cols = self.cols,
        .rows = self.rows[from..to],
    };
}

/// Perform a permutation by re-ordering the rows of this matrix in-place.
///
/// `is` specifies the new order of rows, s.t. `is[i] = j` means that the
/// current row `i` belongs at new position `j`. This operation assumes `is`
/// does constitutes a true permutation, i.e.
///
///   sort(is) == [0, 1, 2, ..., self.height() - 1]
///
/// If this is not the case, behaviour is undefined (the function may loop
/// forever, or panic).
fn permute(self: *Self, is: []usize) !void {
    for (0..is.len) |i| {
        while (is[i] != i) {
            const j = is[i];
            std.mem.swap([*]i64, &self.rows[i], &self.rows[j]);
            std.mem.swap(usize, &is[i], &is[j]);
        }
    }
}

/// Order rows of this matrix in decreasing order by absolute lexicographical
/// value of each row, in-place.
///
/// This operation only works for matrices with up to 16 rows.
fn orderRows(self: *Self) !void {
    std.mem.sort([*]i64, self.rows, self.cols, struct {
        fn lessThan(cols: usize, a: [*]i64, b: [*]i64) bool {
            return std.mem.order(u64, @ptrCast(a[0..cols]), @ptrCast(b[0..cols])) == .gt;
        }
    }.lessThan);
}

/// Run Gaussian Elimination on this augmented matrix, in-place.
///
/// Returns the list of free variables (columns where the pivot is missing),
/// and updates the matrix so that the solution at every row can be framed as:
///
///   Xi = [Ki + ΣMjXj] / Mi
///
/// (An affine formula in terms of free variables).
///
/// Assumes that the last column of the matrix is the constants column, so not
/// tested as a pivot.
pub fn gaussianElimination(self: *Self, a: Allocator) ![]usize {
    const lim = @min(self.width() - 1, self.height());

    var free: ArrayList(usize) = .{};
    errdefer free.deinit(a);

    for (0..lim) |i| {
        var slice_ = self.slice(i, self.height()).?;
        try slice_.orderRows();

        const pivot = slice_.get(i, 0).?;
        if (pivot == 0) {
            // If the pivot is zero, we know that this linear system is free
            // w.r.t. this variable, and because of the ordering operation
            // above, all values below this one in the column are zero as well.
            try free.append(a, i);
        } else for (1..slice_.height()) |r| {
            const under = slice_.get(i, r).?;
            if (under == 0) continue;

            const mult: i64 = @intCast(math.lcm(@abs(pivot), @abs(under)));
            const p_fact = @divExact(mult, pivot);
            const u_fact = @divExact(mult, under);

            for (slice_.rowPtr(0).?, slice_.rowPtr(r).?) |p, *u| {
                u.* = u.* * u_fact - p * p_fact;
            }
        }
    }

    // Any variables that don't have a row and a column are also free.
    for (lim..self.width() - 1) |i| {
        try free.append(a, i);
    }

    // Back propagate pivots, and normalize them all too have positive
    // coefficients.
    var i = lim;
    while (i > 0) : (i -= 1) {
        const pivot = self.get(i - 1, i - 1).?;
        if (pivot == 0) continue;

        for (0..i - 1) |r| {
            const over = self.get(i - 1, r).?;
            if (over == 0) continue;

            const mult: i64 = @intCast(math.lcm(@abs(pivot), @abs(over)));
            const p_fact = @divExact(mult, pivot);
            const o_fact = @divExact(mult, over);

            for (self.rowPtr(i - 1).?, self.rowPtr(r).?) |p, *o| {
                o.* = o.* * o_fact - p * p_fact;
            }
        }

        if (pivot > 0) continue;
        for (self.rowPtr(i - 1).?) |*p| p.* *= -1;
    }

    return free.toOwnedSlice(a);
}

/// Compare two matrices for structural equality.
///
/// Equal matrices have the same dimensions, and corresponding cells contain
/// equal values.
pub fn eql(self: Self, other: Self) bool {
    if (self.cols != other.cols or self.rows.len != other.rows.len) {
        return false;
    }

    const cols = self.cols;
    for (self.rows, other.rows) |r, s| {
        if (!std.mem.eql(i64, r[0..cols], s[0..cols])) {
            return false;
        }
    }

    return true;
}

/// Format the matrix.
///
/// Cells are formatted in decimal, columns are aligned and all wide enough to
/// accommodate the largest value with a sign, and are separated by a single
/// space. Every value will be prefixed with either a '+' or '-' sign.
pub fn format(self: Self, writer: anytype) !void {
    var w: usize = 0;
    for (self.rows) |r| {
        for (r[0..self.cols]) |d| {
            w = @max(w, 1 + if (d == 0) 0 else math.log10(@abs(d)));
        }
    }

    const opts = std.fmt.Options{
        .width = w + 2,
        .alignment = .right,
        .fill = ' ',
    };

    for (self.rows) |r| {
        for (r[0..self.cols]) |d| {
            try writer.printInt(d, 10, std.fmt.Case.lower, opts);
        } else {
            try writer.writeAll("\n");
        }
    }
}

test "permutation" {
    const a = std.testing.allocator;

    var md = [_]i64{
        1, 2, 3,
        4, 5, 6,
        7, 8, 9,
    };

    var nd = [_]i64{
        4, 5, 6,
        7, 8, 9,
        1, 2, 3,
    };

    var m = try Self.new(a, 3, &md);
    defer m.deinit(a);

    var n = try Self.new(a, 3, &nd);
    defer n.deinit(a);

    var is = [_]usize{ 2, 0, 1 };
    try m.permute(&is);
    try std.testing.expect(m.eql(n));
}

test "order rows" {
    const a = std.testing.allocator;

    var md = [_]i64{
        0, 0, 1,
        1, 0, 0,
        0, 1, 0,
    };

    var nd = [_]i64{
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
    };

    var m = try Self.new(a, 3, &md);
    defer m.deinit(a);

    var n = try Self.new(a, 3, &nd);
    defer n.deinit(a);

    try m.orderRows();
    try std.testing.expect(m.eql(n));
}

test "order rows mixed signs" {
    const a = std.testing.allocator;
    var md = [_]i64{
        0, -2, 1,
        1, 0,  0,
        0, 1,  -3,
    };

    var nd = [_]i64{
        1, 0,  0,
        0, -2, 1,
        0, 1,  -3,
    };

    var m = try Self.new(a, 3, &md);
    defer m.deinit(a);

    var n = try Self.new(a, 3, &nd);
    defer n.deinit(a);

    try m.orderRows();
    try std.testing.expect(m.eql(n));
}

test "gaussian elimination" {
    const a = std.testing.allocator;

    {
        var md = [_]i64{
            0, 0, 1, 1, 0, 145,
            1, 0, 1, 0, 1, 136,
            0, 0, 1, 1, 0, 145,
            0, 1, 0, 0, 1,   5,
        };

        var nd = [_]i64{
            1, 0, 0, -1, 1,  -9,
            0, 1, 0,  0, 1,   5,
            0, 0, 1,  1, 0, 145,
            0, 0, 0,  0, 0,   0,
        };

        var m = try Self.new(a, 6, &md);
        defer m.deinit(a);

        var n = try Self.new(a, 6, &nd);
        defer n.deinit(a);

        const free = try m.gaussianElimination(a);
        defer a.free(free);

        try std.testing.expect(m.eql(n));
        try std.testing.expectEqualSlices(usize, &[_]usize{ 3, 4 }, free);
    }

    {
        var md = [_]i64{
            0, 0, 0, 1, 0, 12,
            0, 1, 1, 0, 1, 48,
            0, 0, 1, 1, 1, 45,
            1, 1, 1, 1, 1, 79,
            1, 0, 1, 0, 0, 39,
        };

        var nd = [_]i64{
            2, 0, 0, 0, 0, 38,
            0, 2, 0, 0, 0, 30,
            0, 0, 2, 0, 0, 40,
            0, 0, 0, 2, 0, 24,
            0, 0, 0, 0, 1, 13,
        };

        var m = try Self.new(a, 6, &md);
        defer m.deinit(a);

        var n = try Self.new(a, 6, &nd);
        defer n.deinit(a);

        const free = try m.gaussianElimination(a);
        defer a.free(free);

        try std.testing.expect(m.eql(n));
        try std.testing.expectEqualSlices(usize, &[_]usize{}, free);
    }
}

test "slicing" {
    const a = std.testing.allocator;

    var md = [_]i64{
        1, 2, 3,
        4, 5, 6,
        7, 8, 9,
    };

    var nd = [_]i64{
        4, 5, 6,
        7, 8, 9,
    };

    var od = [_]i64{
        7, 8, 9,
        4, 5, 6,
    };

    var pd = [_]i64{
        1, 2, 3,
        7, 8, 9,
        4, 5, 6,
    };

    var qd = [_]i64{
        7, 0, 9,
        4, 5, 6,
    };

    var m = try Self.new(a, 3, &md);
    defer m.deinit(a);

    var n = try Self.new(a, 3, &nd);
    defer n.deinit(a);

    var o = try Self.new(a, 3, &od);
    defer o.deinit(a);

    var p = try Self.new(a, 3, &pd);
    defer p.deinit(a);

    var q = try Self.new(a, 3, &qd);
    defer q.deinit(a);

    var s = m.slice(1, 3) orelse unreachable;
    try std.testing.expect(n.eql(s));

    var is = [_]usize{ 1, 0 };
    s.permute(&is) catch unreachable;

    try std.testing.expect(o.eql(s));
    try std.testing.expect(m.eql(p));

    m.ptr(1, 1).?.* = 0;
    try std.testing.expect(s.eql(q));
}

test "equality" {
    const a = std.testing.allocator;

    var md = [_]i64{
        1, 2, 3,
        4, 5, 6,
    };

    var nd = [_]i64{
        1, 2, 3,
        4, 5, 6,
    };

    var od = [_]i64{
        1, 2, 3,
        4, 5, 7,
    };

    var m = try Self.new(a, 3, &md);
    defer m.deinit(a);

    var n = try Self.new(a, 3, &nd);
    defer n.deinit(a);

    var o = try Self.new(a, 3, &od);
    defer o.deinit(a);

    try std.testing.expect(m.eql(m));
    try std.testing.expect(m.eql(n));
    try std.testing.expect(!m.eql(o));
}

test "formatting" {
    const a = std.testing.allocator;

    var md = [_]i64{
        1,    23, 456,
        7890, 12, 3,
    };

    var m = try Self.new(a, 3, &md);
    defer m.deinit(a);

    const expect =
        \\    +1   +23  +456
        \\ +7890   +12    +3
        \\
    ;

    var actual: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&actual);
    const writer = stream.writer();
    std.fmt.format(writer, "{f}", .{m}) catch unreachable;

    try std.testing.expectEqualStrings(expect, stream.getWritten());
}
