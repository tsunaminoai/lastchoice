//! The public entry point: a parsed FirstChoice `.FOL` file.
//!
//! Ownership model: every parse output (raw bytes, schema, records, texts,
//! style runs) is allocated in a single arena embedded in the `File`. Freeing
//! is O(1): `deinit` tears down the arena. Nothing is freed individually.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Blocks = @import("blocks.zig");
const Block = Blocks.Block;
const Header = Blocks.Header;
const schema_mod = @import("schema.zig");
const Schema = schema_mod.Schema;
const Text = @import("text.zig");
const value = @import("value.zig");
const Value = value.Value;
const Record = value.Record;

const File = @This();

arena: std.heap.ArenaAllocator,
header: Header,
schema: Schema,
records: []const Record,

/// Reads and parses the file at `path` (relative to cwd) using `io`.
pub fn init(gpa: Allocator, io: std.Io, path: []const u8) !File {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, arena.allocator(), .unlimited);
    const p = try parse(arena.allocator(), raw);
    return .{ .arena = arena, .header = p.header, .schema = p.schema, .records = p.records };
}

/// Parses an in-memory `.FOL` image. `bytes` is copied into the arena, so the
/// caller retains ownership of the input.
pub fn initFromBytes(gpa: Allocator, bytes: []const u8) !File {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const raw = try arena.allocator().dupe(u8, bytes);
    const p = try parse(arena.allocator(), raw);
    return .{ .arena = arena, .header = p.header, .schema = p.schema, .records = p.records };
}

pub fn deinit(self: *File) void {
    self.arena.deinit();
}

const Parsed = struct {
    header: Header,
    schema: Schema,
    records: []const Record,
};

/// Parses `raw` (arena-owned) into its typed components. All allocations use
/// `a`, the owning arena's allocator; the arena itself is never copied here.
fn parse(a: Allocator, raw: []u8) !Parsed {
    const header = try Header.fromBytes(raw[0..128]);
    const blocks = std.mem.bytesAsSlice(Block, raw[128..]);
    const schema = try Schema.parse(a, header, blocks);
    const records = try loadRecords(a, schema, blocks);
    return .{ .header = header, .schema = schema, .records = records };
}

fn loadRecords(a: Allocator, schema: Schema, blocks: Blocks.BlockList) ![]const Record {
    const record_blocks = blocks[schema.first_data_block..];
    var records: std.ArrayList(Record) = .empty;

    var idx: usize = 0;
    while (idx < record_blocks.len) {
        const block = record_blocks[idx];
        if (block.type != .DataRecord) {
            // Skip TableView / Formula / Empty / stray continuation blocks that
            // may follow the record region instead of hard-failing.
            if (block.type != .Empty) {
                std.log.warn("skipping non-record block {s} at index {}", .{
                    @tagName(block.type),
                    schema.first_data_block + idx,
                });
            }
            idx += 1;
            continue;
        }
        const num_blocks = block.data.DataRecord.num_blocks;
        const span = record_blocks[idx .. idx + num_blocks];
        const data = try recordBytes(a, span);
        try records.append(a, try readRecordFields(a, schema, data));
        idx += num_blocks;
    }
    return records.toOwnedSlice(a);
}

/// Concatenates a record's payload across its blocks. The first block carries a
/// 2-byte record header (num_blocks + reserved) before its 124 payload bytes;
/// each continuation block carries a full 126 payload bytes after its type word.
fn recordBytes(a: Allocator, blocks: Blocks.BlockList) ![]u8 {
    var buf = try a.alloc(u8, blocks.len * Blocks.Block_Size);
    var idx: usize = 0;
    for (blocks, 0..) |block, i| {
        if (i == 0) {
            const payload = &block.data.DataRecord.data;
            @memcpy(buf[idx..][0..payload.len], payload);
            idx += payload.len;
        } else {
            const payload = &block.data.common.data;
            @memcpy(buf[idx..][0..payload.len], payload);
            idx += payload.len;
        }
    }
    return buf[0..idx];
}

fn readRecordFields(a: Allocator, schema: Schema, data: []const u8) !Record {
    const cells = try a.alloc(?Value, schema.fields.len);
    @memset(cells, null);

    var bytes: ?[]const u8 = data;
    for (schema.fields, 0..) |field, i| {
        const b = bytes orelse break; // record shorter than schema -> rest blank
        const text = try Text.initFromBytes(a, b);
        bytes = text.extra;
        cells[i] = try cellValue(a, field.kind, text);
    }

    return .{ .cells = cells };
}

fn cellValue(a: Allocator, kind: value.Kind, text: Text) !?Value {
    const raw = text.asSlice();
    if (raw.len == 0) return null; // blank cell
    return switch (kind) {
        .general => .{ .general = try text.toStyledText(a) },
        .time => .{ .time = try text.toStyledText(a) },
        .numeric => .{ .numeric = value.parseNumeric(raw) catch |err| {
            std.log.warn("unparseable numeric '{s}': {s}", .{ raw, @errorName(err) });
            return null;
        } },
        .date => .{ .date = value.parseDate(raw) catch |err| {
            std.log.warn("unparseable date '{s}': {s}", .{ raw, @errorName(err) });
            return null;
        } },
        .boolean => .{ .boolean = raw[0] == 'Y' or raw[0] == 'y' },
    };
}

/// Prints the records as a tab-separated table (header row + one row per
/// record). Blank cells render as empty. Retained for the `print` subcommand.
pub fn print(self: File, writer: *std.Io.Writer) !void {
    for (self.schema.fields) |field| {
        try writer.print("{s}\t", .{field.name});
    }
    try writer.writeAll("\n");
    for (self.records) |record| {
        for (record.cells) |cell| {
            if (cell) |v| {
                try writer.print("{f}", .{v});
            }
            try writer.writeAll("\t");
        }
        try writer.writeAll("\n");
    }
}

test "File parses TESTDB.FOL" {
    var file = try File.init(std.testing.allocator, std.testing.io, "test/TESTDB.FOL");
    defer file.deinit();

    try std.testing.expectEqual(@as(usize, 5), file.schema.fields.len);
    try std.testing.expect(file.records.len > 0);
}
