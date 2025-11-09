const std = @import("std");
const Block = @import("block.zig");
const Field = @import("field.zig");

const Schema = @This();

fields: std.ArrayList(Field),
alloc: std.mem.Allocator,
data: []u8,

lines_in_form_screen: u16 = 0,
lines_length: u16 = 0,

pub fn init(
    allocator: std.mem.Allocator,
    header: Block.Header,
    blocks: Block.BlockList,
) !Schema {
    var self = Schema{
        .alloc = allocator,
        .fields = std.ArrayList(Field){},
        .data = undefined,
    };

    self.data = try self.readDataFromBlocks(header, blocks);

    try self.parseFields(header);
    errdefer self.deinit();

    return self;
}

fn parseFields(self: *Schema, header: Block.Header) !void {
    var fields = std.ArrayList(Field){};
    errdefer fields.deinit(self.alloc);

    var f = try Field.init(self.alloc, self.data);
    errdefer f.deinit();
    try fields.append(self.alloc, f);

    while (f.remaining) |raw| {
        f = try Field.init(self.alloc, raw);
        errdefer f.deinit();
        try fields.append(self.alloc, f);
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
    header: Block.Header,
    blocks: Block.BlockList,
) ![]u8 {
    const first_block = blocks[header.formDefinitionIndex];

    const num_schema_blocks = std.mem.readInt(u16, first_block.data[0..2], .little);
    self.lines_in_form_screen = std.mem.readInt(u16, first_block.data[2..4], .big);
    // lines_length = std.mem.readInt(u16, first_block.data[4..6], .big);
    // std.debug.print("{d} blocks in the form\n", .{num_schema_blocks});

    var d = try self.alloc.alloc(u8, num_schema_blocks * 128);
    errdefer self.alloc.free(d);

    @memset(d, 0);

    @memcpy(d[0..120], first_block.data[6..]);
    var idx: usize = 120;

    for (1..num_schema_blocks) |i| {
        const block = blocks[header.formDefinitionIndex + i];
        @memcpy(d[idx .. idx + block.data.len], &block.data);
        idx += 126;
    }
    return d;
    // std.debug.print("{d} lines in the form screen\n", .{lines_in_form_screen});
    // std.debug.print("{d} length of lines\n", .{lines_length});
    // std.debug.print("{}", .{header});
    // std.debug.print("Length of form data: {}, {}\n", .{ data.len, header.availableDBFields + header.formLength });
}

pub fn deinit(self: *Schema) void {
    for (self.fields.items) |*field| {
        field.deinit();
    }
    self.fields.deinit(self.alloc);
    self.alloc.free(self.data);
}
