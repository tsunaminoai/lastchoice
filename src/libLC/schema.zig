const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;
const Blocks = @import("blocks.zig");
const Text = @import("text.zig");
const Field = @import("field.zig");

const Schema = @This();

allocator: std.mem.Allocator,
lines_on_screen: u16 = 0,
lines_length: u16 = 0,
fields: Array(Field),
num_fields: usize = 0,
first_data_block: usize = 0,

pub fn init(
    allocator: std.mem.Allocator,
    header: Blocks.Header,
    blocks: Blocks.BlockList,
) !*Schema {
    const self = try allocator.create(Schema);
    self.allocator = allocator;
    self.fields = Array(Field).init(allocator);
    self.num_fields = header.availableDBFields;
    errdefer allocator.destroy(self);
    {
        try self.readDataFromBlocks(header, blocks);

        // try self.readFields(header);
    }
    errdefer self.deinit();

    return self;
}
pub fn deinit(self: *Schema) void {
    for (self.fields.items) |field| {
        field.deinit();
    }
    self.fields.deinit();
}

fn readDataFromBlocks(
    self: *Schema,
    header: Blocks.Header,
    blocks: Blocks.BlockList,
) !void {
    const first_block = blocks[header.formDefinitionIndex];
    if (first_block.type != .FormDescriptionView) {
        std.log.err("Incorrect block found at specified index {}", .{header.formDefinitionIndex});
        return error.InvalidBlockType;
    }
    const form_data = first_block.data.Schema.swapEndien();
    self.lines_length = form_data.len_lines;
    self.lines_on_screen = form_data.len_lines_on_screen;
    std.debug.print("{}\n", .{form_data});

    var field_data = try self.allocator.alloc(u8, form_data.num_blocks * 128);
    defer self.allocator.free(field_data);
    @memset(field_data, 0);

    field_data[0..form_data.data.len].* = form_data.data;

    var idx: usize = form_data.data.len;

    for (1..form_data.num_blocks) |i| {
        const nextblock = blocks[header.formDefinitionIndex + i];
        if (nextblock.type != .FormDescriptionContinuation) {
            std.log.err("Incorrect block type found at index {}", .{header.formDefinitionIndex + i});
            return error.InvalidBlockType;
        }
        @memcpy(field_data[idx .. idx + nextblock.data.common.data.len], &nextblock.data.common.data);
        idx += nextblock.data.common.data.len;
    }
    self.first_data_block = header.formDefinitionIndex + form_data.num_blocks;

    try self.readFields(field_data[0..idx]);
}

fn readFields(self: *Schema, data: []const u8) !void {
    // std.debug.print("(len:{}) {X}\n", .{ data.len, data });
    //     var fields = std.ArrayList(*Field.Base).init(self.allocator);
    //     errdefer fields.deinit();
    var bytes: ?[]const u8 = data;
    while (bytes) |d| {
        var name = try Text.initFromBytes(self.allocator, d);
        errdefer name.deinit();

        var field = try Field.init(self.allocator, name);
        errdefer field.deinit();

        try self.fields.append(field);
        // std.debug.print("Found field: {} {} of {}\n", .{ field, self.fields.items.len, self.num_fields });
        bytes = name.extra;
    }

    std.debug.print("Found {} Fields\n", .{self.fields.items.len});
    // for (self.fields.items) |field| {
    //     std.debug.print("'{s}'\t{s}\n", .{ field.name.string.items, @tagName(field.value) });
    // }
}
