const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;
const Blocks = @import("blocks.zig");
const Schema = @import("schema.zig");
const FOL = @import("fol.zig");

const LCFile = @This();

fol: *FOL,
raw: []u8,
allocator: Allocator,

pub fn init(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !LCFile {
    const fol = try allocator.create(FOL);
    errdefer allocator.destroy(fol);

    const r = try std.Io.Dir.cwd().readFileAlloc(io, file_path, allocator, .unlimited);
    errdefer allocator.free(r);

    fol.* = try FOL.init(allocator, r);

    return .{
        .fol = fol,
        .raw = r,
        .allocator = allocator,
    };
}

pub fn deinit(self: *LCFile) void {
    self.fol.deinit();
    self.allocator.destroy(self.fol);
    self.allocator.free(self.raw);
}

test "LCFile" {
    const allocator = std.testing.allocator;
    var file = try init(allocator, std.testing.io, "test/TESTDB.FOL");
    defer file.deinit();

    try std.testing.expectEqual(file.fol.blocks.len, file.fol.header.totalFileBlocks);

    const block = file.fol.blocks[0];
    _ = block;
}
