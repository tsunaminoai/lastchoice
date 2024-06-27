const std = @import("std");
const Block = @import("block.zig");
const Schema = @import("schema.zig");
const Record = @import("record.zig");

const LCFile = @This();

blocks: Block.BlockList,
header: Block.Header,
schema: *Schema = undefined,

var raw: []u8 = undefined;
var alloc: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !*LCFile {
    const self = try allocator.create(LCFile);
    errdefer allocator.destroy(self);

    alloc = allocator;
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    raw = try file.readToEndAlloc(
        alloc,
        std.math.maxInt(u32),
    );
    errdefer alloc.free(raw);
    self.* = .{
        .header = try Block.Header.fromBytes(raw[0..128]),
        .blocks = try Block.fromBytes(raw[128..]),
    };
    self.schema = try Schema.init(alloc, self.header, self.blocks);
    errdefer self.deinit();

    const r: Record = undefined;
    _ = r; // autofix

    return self;
}

pub fn deinit(self: *LCFile) void {
    self.schema.deinit();
    alloc.free(raw);
    alloc.destroy(self);
}

test "LCFile" {
    const allocator = std.testing.allocator;
    var file = try LCFile.init(allocator, "RESERVE.FOL");
    defer file.deinit();

    // try std.testing.expectEqual(raw.len, file.header.totalFileBlocks * 128 + 128);
    try std.testing.expectEqual(file.blocks.len, file.header.totalFileBlocks);

    const block = file.blocks[0];
    try std.testing.expectEqual(block.type, Block.Type.Empty);
    // for (file.blocks) |b| {
    //     std.debug.print("{s}\n", .{@tagName(b.type)});
    // }
}
