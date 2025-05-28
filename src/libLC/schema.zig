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

pub fn init(
    allocator: std.mem.Allocator,
    header: Blocks.Header,
    blocks: Blocks.BlockList,
) !*Schema {
    const self = try allocator.create(Schema);
    self.allocator = allocator;
    self.fields = Array(Field).init(allocator);
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

// fn readFields(self: *Schema, header: Blocks.Header) !void {
//     var fields = std.ArrayList(*Field.Base).init(self.allocator);
//     errdefer fields.deinit();

//     var name = try Text.initFromBytes(self.allocator, data);
//     errdefer name.deinit();

//     var f = if (name.field_type) |t| try Field.Base.init(alloc, name, t) else {
//         std.debug.print("Field tag not found for field name text: {}\n", .{name});
//         return error.FieldTypeNotFound;
//     };
//     errdefer f.deinit();
//     // std.debug.print("Found field: {}\n", .{name});

//     try fields.append(f);
//     var bytes_read: usize = name.len;

//     while (bytes_read < data.len) {
//         name = try Text.initFromBytes(alloc, data[bytes_read..data.len]);
//         std.debug.print("We've read {} bytes\n", .{bytes_read});
//         f = if (name.field_type) |t| try Field.Base.init(alloc, name, t) else {
//             std.debug.print("Field tag not found for field name text: {}\n", .{name});
//             return error.FieldTypeNotFound;
//         };
//         errdefer f.deinit();
//         // std.debug.print("Found field: {}\n", .{name});
//         try fields.append(f);
//         if (fields.items.len >= header.availableDBFields) break;
//         bytes_read += name.len;
//     }
//     self.fields = fields;
//     std.debug.print("Found {} Fields\n", .{fields.items.len});
//     for (fields.items) |field| {
//         std.debug.print("'{s}'\t{s}\n", .{ field.name.string.items, @tagName(field.type) });
//     }
// }

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

    // @memcpy(data[0..first_block.data.len], &first_block.data);
    var idx: usize = form_data.data.len;

    for (1..form_data.num_blocks) |i| {
        const nextblock = blocks[header.formDefinitionIndex + i];
        if (nextblock.type != .FormDescriptionContinuation) {
            std.log.err("Incorrect block type found at index {}", .{header.formDefinitionIndex + i});
            return error.InvalidBlockType;
        }
        @memcpy(field_data[idx .. idx + nextblock.data.common.data.len], &nextblock.data.common.data);
        idx += nextblock.data.common.data.len;
        // idx += nextblock.data.len;
    }
    std.debug.print("{X}\n", .{field_data});
}
