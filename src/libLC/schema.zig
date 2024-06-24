const std = @import("std");
const Block = @import("block.zig");

var alloc: std.mem.Allocator = undefined;

const Schema = @This();

var data: []u8 = undefined;

pub fn init(
    allocator: std.mem.Allocator,
    header: Block.Header,
    blocks: []align(1) Block,
) !*Schema {
    alloc = allocator;
    const self = try alloc.create(Schema);
    try self.readDataFromBlocks(header, blocks);

    return self;
}

fn readDataFromBlocks(
    self: *Schema,
    header: Block.Header,
    blocks: []align(1) Block,
) !void {
    _ = self; // autofix

    const first_block = blocks[header.formDefinitionIndex - 1];
    const num_schema_blocks = std.mem.readInt(u16, first_block.data[0..2], .little);
    std.debug.print("{d} blocks in the form\n", .{num_schema_blocks});

    data = try alloc.alloc(u8, num_schema_blocks * 124);
    @memcpy(data[0..120], first_block.data[6..]);
    for (0..num_schema_blocks - 1) |i| {
        const block = blocks[header.formDefinitionIndex + i];
        @memcpy(data[i * 124 .. i * 124 + 124], block.data[2..]);
    }
    std.debug.print("{any}", .{data});
}

pub fn deinit(self: *Schema) void {
    alloc.free(data);
    alloc.destroy(self);
}
