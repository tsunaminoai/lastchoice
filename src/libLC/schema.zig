const std = @import("std");
const Block = @import("block.zig");
const Field = @import("field.zig");

fields: std.ArrayList(*Field),

const Schema = @This();

var alloc: std.mem.Allocator = undefined;
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
    try self.parseFields(header);

    return self;
}

fn parseFields(self: *Schema, header: Block.Header) !void {
    _ = header; // autofix

    var fields = std.ArrayList(*Field).init(alloc);

    var f = try Field.init(alloc, data[0..]);
    try fields.append(f);

    while (f.remaining) |raw| {
        if (std.mem.readInt(u16, raw[0..2], .big) == 0) break;
        f = try Field.init(alloc, raw);
        try fields.append(f);
    }
    self.fields = fields;
    std.debug.print("Found {} Fields\n", .{fields.items.len});
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
    @memset(data, 0);

    lines_in_form_screen = std.mem.readInt(u16, first_block.data[2..4], .big);
    lines_length = std.mem.readInt(u16, first_block.data[4..6], .big);

    @memcpy(data[0..120], first_block.data[6..]);

    for (0..num_schema_blocks - 1) |i| {
        const block = blocks[header.formDefinitionIndex + i];
        @memcpy(data[i * form_data_len .. i * form_data_len + form_data_len], block.data[2..]);
    }

    std.debug.print("{d} lines in the form screen\n", .{lines_in_form_screen});
    std.debug.print("{d} length of lines\n", .{lines_length});
    std.debug.print("{}", .{header});
}

pub fn deinit(self: *Schema) void {
    for (self.fields.items) |field| {
        field.deinit();
    }
    self.fields.deinit();
    alloc.free(data);
    alloc.destroy(self);
}
