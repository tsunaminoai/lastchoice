const std = @import("std");
const Block = @import("block.zig");

const LCFile = @This();

blocks: []align(1) Block,

var raw: []u8 = undefined;
var alloc: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !*LCFile {
    const self = try allocator.create(LCFile);

    alloc = allocator;
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    raw = try file.readToEndAlloc(
        alloc,
        std.math.maxInt(u32),
    );
    self.* = .{
        .blocks = try Block.fromBytes(raw[128..]),
    };

    return self;
}

pub fn deinit(self: *LCFile) void {
    alloc.free(raw);
    alloc.destroy(self);
}

test "LCFile" {
    const allocator = std.testing.allocator;
    var file = try LCFile.init(allocator, "RESERVE.FOL");
    defer file.deinit();

    try std.testing.expectEqual(raw.len, 3712);
    try std.testing.expectEqual(file.blocks.len, (3712 / 128) - 1);

    const block = file.blocks[0];
    try std.testing.expectEqual(block.type, Block.Type.Empty);
}
