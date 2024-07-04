const std = @import("std");
const Blocks = @import("blocks.zig");
const Text = @import("text.zig");
const Field = @import("field.zig");

fields: std.ArrayList(*Field.Base),
num_blocks: usize = 0,

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
    var fields = std.ArrayList(*Field.Base).init(alloc);
    errdefer fields.deinit();

    var name = try Text.initFromBytes(alloc, data);
    errdefer name.deinit();

    var f = if (name.field_type) |t| try Field.Base.init(alloc, name, t) else {
        std.debug.print("Field tag not found for field name text: {}\n", .{name});
        return error.FieldTypeNotFound;
    };
    errdefer f.deinit();
    // std.debug.print("Found field: {}\n", .{name});

    try fields.append(f);
    var bytes_read: usize = name.len;

    while (bytes_read < data.len) {
        name = try Text.initFromBytes(alloc, data[bytes_read..data.len]);
        std.debug.print("We've read {} bytes\n", .{bytes_read});
        f = if (name.field_type) |t| try Field.Base.init(alloc, name, t) else {
            std.debug.print("Field tag not found for field name text: {}\n", .{name});
            return error.FieldTypeNotFound;
        };
        errdefer f.deinit();
        // std.debug.print("Found field: {}\n", .{name});
        try fields.append(f);
        if (fields.items.len >= header.availableDBFields) break;
        bytes_read += name.len;
    }
    self.fields = fields;
    std.debug.print("Found {} Fields\n", .{fields.items.len});
    for (fields.items) |field| {
        std.debug.print("'{s}'\t{s}\n", .{ field.name.string.items, @tagName(field.type) });
    }
}

fn readDataFromBlocks(
    self: *Schema,
    header: Blocks.Header,
    blocks: Blocks.BlockList,
) !void {
    const first_block = blocks[header.formDefinitionIndex].FormDescriptionView.convert();

    // const num_schema_blocks = std.mem.readInt(u16, first_block.data[0..2], .little);
    // lines_in_form_screen = std.mem.readInt(u16, first_block.data[2..4], .big);
    // lines_length = std.mem.readInt(u16, first_block.data[4..6], .big);
    // std.debug.print("{d} blocks in the form\n", .{num_schema_blocks});
    std.debug.print("{any}\n", .{header});
    std.debug.print("{any}\n", .{first_block});
    self.num_blocks = first_block.num_blocks;
    data = try alloc.alloc(u8, first_block.num_blocks * Blocks.Block_Size);
    errdefer self.deinit();

    @memset(data, 0);

    @memcpy(data[0..first_block.data.len], &first_block.data);
    var idx: usize = first_block.data.len;

    for (1..first_block.num_blocks) |i| {
        const continuation = blocks[header.formDefinitionIndex + i].FormDescriptionContinuation;
        @memcpy(data[idx .. idx + continuation.data.len], &continuation.data);
        idx += continuation.data.len;
    }
    std.debug.print("{X}\n", .{data});

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
