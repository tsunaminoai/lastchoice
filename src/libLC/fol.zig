const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;
const Blocks = @import("blocks.zig");
const Block = Blocks.Block;
const Header = Blocks.Header;
const Schema = @import("schema.zig");
const Field = @import("field.zig");
const Text = @import("text.zig");

const FOL = @This();

const Record = Array(Field.Value);

header: Header,
blocks: []align(1) Block,
schema: *Schema,
records: Array(Record),
allocator: Allocator,

pub fn init(alloc: Allocator, buffer: []u8) !FOL {
    var f: FOL = .{
        .header = try Header.fromBytes(buffer[0..128]),
        .blocks = std.mem.bytesAsSlice(Block, buffer[128..]),
        .schema = undefined,
        .records = Array(Record).init(alloc),
        .allocator = alloc,
    };
    f.schema = try Schema.init(alloc, f.header, f.blocks);
    errdefer f.schema.deinit();

    try f.loadRecords();
    return f;
}
pub fn deinit(self: *FOL) void {
    self.schema.deinit();
    // self.records.deinit();
    // No need to free blocks, they are part of the buffer
}
fn loadRecords(self: *FOL) !void {
    const record_blocks = self.blocks[self.schema.first_data_block..];
    if (record_blocks.len == 0) {
        std.log.err("No record blocks found in the file", .{});
        return error.NoRecordsFound;
    }
    var idx: usize = 0;
    while (idx < record_blocks.len) {
        const block = record_blocks[idx];
        if (block.type != .DataRecord) {
            std.log.err("Expected DataRecord block, found: {s}", .{@tagName(block.type)});
            return error.InvalidBlockType;
        }
        const dr = block.data.DataRecord;
        try self.loadRecordFromBlocks(record_blocks[idx .. idx + dr.num_blocks]);
        idx += dr.num_blocks;
        // std.debug.print("{}", .{block.data.DataRecord});

        // Store the record in the hash map
        // try self.records.put(key, value);

    }
}

fn loadRecordFromBlocks(self: *FOL, blocks: []align(1) Block) !void {
    var record_data = try self.allocator.alloc(u8, blocks.len * Blocks.Block_Size);
    defer self.allocator.free(record_data);
    @memset(record_data, 0);
    var idx: usize = 0;
    for (blocks) |block| {
        const dr = block.data.DataRecord;
        @memcpy(record_data[idx .. idx + dr.data.len], dr.data[0..dr.data.len]);
        idx += dr.data.len;
    }

    std.debug.print("{X:0.2}", .{record_data});
    const record = try self.readRecordFields(record_data);
    try self.records.append(record);
}

fn readRecordFields(self: *FOL, data: []const u8) !Record {
    var record: Record = Record.init(self.allocator);
    errdefer record.deinit();

    var bytes: ?[]const u8 = data;
    for (self.schema.fields.items) |field| {
        if (bytes) |b| {
            std.debug.print("from rrf(): {X}\n", .{b});
            const value_text = try Text.initFromBytes(self.allocator, b);
            std.debug.print("Value text: {}\n", .{value_text});
            const value = try Field.Value.fromSlice(field.value, self.allocator, value_text.string.items);

            try record.append(value);
            bytes = value_text.extra;
        }
    }
    // std.debug.print("Found {} Fields\n", .{self.fields.items.len});
    // for (self.fields.items) |field| {
    //     std.debug.print("'{s}'\t{s}\n", .{ field.name.string.items, @tagName(field.value) });
    // }
    return record;
}

test {
    var buf: [4096]u8 = undefined;
    var f = try std.fs.cwd().openFile("test/TESTDB.FOL", .{});
    defer f.close();

    const n = try f.readAll(&buf);
    const file = FOL.init(buf[0..n]);
    std.debug.print("Header: {}\n", .{file.header});
    std.debug.print("FDV: {}\n", .{file.blocks[file.header.schemaPosition()].data.Schema});
}
