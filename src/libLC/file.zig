const std = @import("std");
const Block = @import("block.zig");
const Schema = @import("schema.zig");

const LCFile = @This();

blocks: Block.BlockList,
header: Block.Header,
schema: Schema,

raw: []u8 = undefined,
alloc: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !LCFile {
    var self = LCFile{
        .alloc = allocator,
        .blocks = undefined,
        .header = undefined,
        .schema = undefined,
        .raw = undefined,
    };

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    self.raw = try file.readToEndAlloc(
        self.alloc,
        std.math.maxInt(u32),
    );
    errdefer self.alloc.free(self.raw);
    self.header = try Block.Header.fromBytes(self.raw[0..128]);
    self.blocks = try Block.fromBytes(self.raw[128..]);
    self.schema = try Schema.init(self.alloc, self.header, self.blocks);
    errdefer self.deinit();

    return self;
}

pub fn deinit(self: *LCFile) void {
    self.schema.deinit();
    self.alloc.free(self.raw);
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
