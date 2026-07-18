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

pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !LCFile {
    const fol = try allocator.create(FOL);
    errdefer allocator.destroy(fol);

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const r = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
    errdefer allocator.free(r);

    fol.* = try FOL.init(allocator, r);

    return .{
        .fol = fol,
        .raw = r,
        .allocator = allocator,
    };
}

pub fn deinit(self: *LCFile) void {
    // self.schema.deinit();
    self.allocator.free(self.raw);
    self.allocator.destroy(self);
}

test "LCFile" {
    const allocator = std.testing.allocator;
    const file = try init(allocator, "test/TESTDB.FOL");
    defer deinit(file);

    // try std.testing.expectEqual(raw.len, file.header.totalFileBlocks * 128 + 128);
    try std.testing.expectEqual(file.blocks.len, file.header.totalFileBlocks);

    const block = file.blocks[0];
    _ = block; // autofix
    // try std.testing.expectEqual(std.meta.activeTag(block), .Empty);
    // for (file.blocks) |b| {
    //     std.debug.print("{s}\n", .{@tagName(b.type)});
    // }
}
