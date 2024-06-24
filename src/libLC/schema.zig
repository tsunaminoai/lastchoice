const std = @import("std");
const Block = @import("block.zig");

var alloc: std.mem.Allocator = undefined;

const Schema = @This();

var data: []u8 = undefined;

var lines_in_form_screen: u16 = 0;
var lines_length: u16 = 0;

pub fn init(
    allocator: std.mem.Allocator,
    header: Block.Header,
    blocks: Block.BlockList,
) !*Schema {
    alloc = allocator;
    const self = try alloc.create(Schema);
    try self.readDataFromBlocks(header, blocks);

    return self;
}

fn readDataFromBlocks(
    self: *Schema,
    header: Block.Header,
    blocks: Block.BlockList,
) !void {
    _ = self; // autofix

    const form_data_len = 124;
    const first_block = blocks[header.formDefinitionIndex - 1];
    const num_schema_blocks = std.mem.readInt(u16, first_block.data[0..2], .little);
    std.debug.print("{d} blocks in the form\n", .{num_schema_blocks});

    data = try alloc.alloc(u8, num_schema_blocks * form_data_len);

    lines_in_form_screen = std.mem.readInt(u16, first_block.data[2..4], .big);
    lines_length = std.mem.readInt(u16, first_block.data[4..6], .big);

    @memcpy(data[0..120], first_block.data[6..]);

    for (0..num_schema_blocks - 1) |i| {
        const block = blocks[header.formDefinitionIndex + i];
        @memcpy(data[i * form_data_len .. i * form_data_len + form_data_len], block.data[2..]);
    }

    std.debug.print("{d} lines in the form screen\n", .{lines_in_form_screen});
    std.debug.print("{d} length of lines\n", .{lines_length});
}

pub fn deinit(self: *Schema) void {
    alloc.free(data);
    alloc.destroy(self);
}
