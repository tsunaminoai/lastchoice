const std = @import("std");
const Blocks = @import("blocks.zig");
const Text = @import("text.zig");
const Field = @import("field.zig");

fields: std.ArrayList(Field),

const Schema = @This();

var alloc: std.mem.Allocator = undefined;
var data: []u8 = undefined;

var lines_in_form_screen: u16 = 0;
var lines_length: u16 = 0;

pub fn init(
    allocator: std.mem.Allocator,
    header: Blocks.Header,
    blocks: Blocks.BlockList,
) !*Schema {
    alloc = allocator;
    const self = try alloc.create(Schema);
    {
        try self.readDataFromBlocks(header, blocks);

        try self.readFields(header);
    }
    errdefer self.deinit();

    return self;
}

fn readFields(self: *Schema, header: Blocks.Header) !void {
    var fields = std.ArrayList(Field.Field(Field.TypeTag)).init(alloc);
    errdefer fields.deinit();

    var name = try Text.init(alloc, data);
    errdefer name.deinit();
    var f = switch (name.field_type.?) {
        .General => try Field.Field(.General).init(alloc, name),
        else => undefined,
    };
    errdefer f.deinit();

    try fields.append(f);

    while (f.remaining) |raw| {
        name = try Text.init(alloc, raw);
        f = try Field.init(alloc, name);
        errdefer f.deinit();
        try fields.append(f);
        if (fields.items.len >= header.availableDBFields) break;
    }
    self.fields = fields;
    std.debug.print("Found {} Fields\n", .{fields.items.len});
    for (fields.items) |field| {
        std.debug.print("'{s}'\t{s}\n", .{ field.string.items, @tagName(field.type) });
    }
}

fn readDataFromBlocks(
    self: *Schema,
    header: Blocks.Header,
    blocks: Blocks.BlockList,
) !void {
    const first_block = blocks[header.formDefinitionIndex].FormDescriptionView;

    // const num_schema_blocks = std.mem.readInt(u16, first_block.data[0..2], .little);
    // lines_in_form_screen = std.mem.readInt(u16, first_block.data[2..4], .big);
    // lines_length = std.mem.readInt(u16, first_block.data[4..6], .big);
    // std.debug.print("{d} blocks in the form\n", .{num_schema_blocks});

    data = try alloc.alloc(u8, first_block.num_blocks * @sizeOf(Blocks.Block));
    errdefer self.deinit();

    @memset(data, 0);

    @memcpy(data, &first_block.data);
    var idx: usize = first_block.data.len;

    for (1..first_block.num_blocks) |i| {
        const block = blocks[header.formDefinitionIndex + i].FormDescriptionContinuation;
        @memcpy(data[idx .. idx + block.data.len], &block.data);
        idx += block.data.len;
    }

    // std.debug.print("{d} lines in the form screen\n", .{lines_in_form_screen});
    // std.debug.print("{d} length of lines\n", .{lines_length});
    // std.debug.print("{}", .{header});
    // std.debug.print("Length of form data: {}, {}\n", .{ data.len, header.availableDBFields + header.formLength });
}

pub fn deinit(self: *Schema) void {
    for (self.fields.items) |field| {
        field.deinit();
    }
    self.fields.deinit();
    alloc.free(data);
    alloc.destroy(self);
}
