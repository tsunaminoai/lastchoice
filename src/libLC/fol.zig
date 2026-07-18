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
        .records = .empty,
        .allocator = alloc,
    };
    f.schema = try Schema.init(alloc, f.header, f.blocks);
    errdefer f.schema.deinit();

    try f.loadRecords();
    return f;
}
pub fn deinit(self: *FOL) void {
    for (self.records.items) |*record| {
        for (record.items) |value| value.deinit();
        record.deinit(self.allocator);
    }
    self.records.deinit(self.allocator);
    self.schema.deinit();
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

    // std.debug.print("{X:0.2}", .{record_data});
    const record = try self.readRecordFields(record_data);
    try self.records.append(self.allocator, record);
}

fn readRecordFields(self: *FOL, data: []const u8) !Record {
    var record: Record = .empty;
    errdefer record.deinit(self.allocator);

    var bytes: ?[]const u8 = data;
    for (self.schema.fields.items) |field| {
        if (bytes) |b| {
            // std.debug.print("from rrf(): {X}\n", .{b});
            const value_text = try Text.initFromBytes(self.allocator, b);
            // std.debug.print("Value text: {}\n", .{value_text});
            const value = try Field.Value.fromSlice(field.value, self.allocator, value_text.string.items);

            try record.append(self.allocator, value);
            bytes = value_text.extra; // slice into the record buffer, not value_text's own memory
            value_text.deinit();
        }
    }
    // std.debug.print("Found {} Fields\n", .{self.fields.items.len});
    // for (self.fields.items) |field| {
    //     std.debug.print("'{s}'\t{s}\n", .{ field.name.string.items, @tagName(field.value) });
    // }
    return record;
}

pub fn print_records(self: FOL, writer: anytype) !void {
    for (self.schema.fields.items) |field| {
        try writer.print("{s}\t", .{field.name.asSlice()});
    }
    try writer.writeAll("\n");
    for (self.records.items) |record| {
        for (record.items) |value| {
            try writer.print("{f}|\t", .{value});
        }
        try writer.writeAll("\n");
    }
}

test "load records from TESTDB.FOL" {
    const alloc = std.testing.allocator;

    const raw = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "test/TESTDB.FOL",
        alloc,
        .unlimited,
    );
    defer alloc.free(raw);

    var f = try FOL.init(alloc, raw);
    defer f.deinit();

    try std.testing.expectEqual(f.header.availableDBFields, f.schema.fields.items.len);
    try std.testing.expect(f.records.items.len > 0);
}
