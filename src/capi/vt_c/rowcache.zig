const std = @import("std");
const Allocator = std.mem.Allocator;

pub const RowCache = struct {
    data: []u64,
    rows: u16,
    cols: u16,

    pub fn init(alloc: Allocator, rows: u16, cols: u16) !RowCache {
        const count: usize = @as(usize, rows) * @as(usize, cols);
        const buf = try alloc.alloc(u64, count);
        @memset(buf, 0);
        return .{ .data = buf, .rows = rows, .cols = cols };
    }

    pub fn deinit(self: *RowCache, alloc: Allocator) void {
        if (self.data.len != 0) alloc.free(self.data);
        self.* = .{ .data = &[_]u64{}, .rows = 0, .cols = 0 };
    }

    pub fn ensure(self: *RowCache, alloc: Allocator, rows: u16, cols: u16) !void {
        if (self.rows == rows and self.cols == cols and self.data.len != 0) return;
        self.deinit(alloc);
        self.* = try RowCache.init(alloc, rows, cols);
    }

    pub inline fn rowSlice(self: *RowCache, row: usize) []u64 {
        const cols: usize = self.cols;
        return self.data[row * cols .. (row + 1) * cols];
    }
};

