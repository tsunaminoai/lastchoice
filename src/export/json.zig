//! JSON exporter. Emits a single object:
//!   {
//!     "fields":     [ {"name": <original>, "kind": <kind>}, ... ],
//!     "records":    [ { <dedup-key>: <typed value|null>, ... }, ... ],
//!     "formatting": [ {"record":R,"field":F,"start":S,"len":L,"bold":true,...}, ... ]
//!   }
//! Record values are typed: strings for general/time, ISO strings for dates,
//! numbers for numerics, booleans for booleans, and JSON null for blanks. Style
//! flags in `formatting` are emitted only when true, and only non-default runs
//! appear.

const std = @import("std");
const lc = @import("lc");
const common = @import("common.zig");

/// Writes `file` as JSON to `writer`. `gpa` backs column-name prep and a small
/// scratch buffer for date formatting.
pub fn write(gpa: std.mem.Allocator, file: lc.File, writer: *std.Io.Writer) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    const keys = try common.prepareColumnNames(a, file.schema.fields);

    var scratch: std.Io.Writer.Allocating = .init(a);

    var jw: std.json.Stringify = .{ .writer = writer, .options = .{ .whitespace = .indent_2 } };

    try jw.beginObject();

    // fields
    try jw.objectField("fields");
    try jw.beginArray();
    for (file.schema.fields) |field| {
        try jw.beginObject();
        try jw.objectField("name");
        try jw.write(field.name);
        try jw.objectField("kind");
        try jw.write(@tagName(field.kind));
        try jw.endObject();
    }
    try jw.endArray();

    // records
    try jw.objectField("records");
    try jw.beginArray();
    for (file.records) |record| {
        try jw.beginObject();
        for (record.cells, keys) |cell, key| {
            try jw.objectField(key);
            try writeCell(&jw, &scratch, cell);
        }
        try jw.endObject();
    }
    try jw.endArray();

    // formatting (non-default runs only)
    try jw.objectField("formatting");
    try jw.beginArray();
    for (file.records, 0..) |record, r| {
        for (record.cells, 0..) |cell, fld| {
            const runs = cellRuns(cell) orelse continue;
            for (runs) |run| {
                try jw.beginObject();
                try jw.objectField("record");
                try jw.write(r);
                try jw.objectField("field");
                try jw.write(fld);
                try jw.objectField("start");
                try jw.write(run.start);
                try jw.objectField("len");
                try jw.write(run.len);
                if (run.style.bold) {
                    try jw.objectField("bold");
                    try jw.write(true);
                }
                if (run.style.underline) {
                    try jw.objectField("underline");
                    try jw.write(true);
                }
                if (run.style.italic) {
                    try jw.objectField("italic");
                    try jw.write(true);
                }
                if (run.style.background) {
                    try jw.objectField("background");
                    try jw.write(true);
                }
                try jw.endObject();
            }
        }
    }
    try jw.endArray();

    try jw.endObject();
}

fn writeCell(jw: *std.json.Stringify, scratch: *std.Io.Writer.Allocating, cell: ?lc.Value) !void {
    const v = cell orelse return jw.write(null);
    switch (v) {
        .general => |g| try jw.write(g.text),
        .time => |t| try jw.write(t.text),
        .numeric => |num| try jw.write(num),
        .boolean => |b| try jw.write(b),
        .date => |d| {
            scratch.clearRetainingCapacity();
            try d.writeIso(&scratch.writer);
            try jw.write(scratch.written());
        },
    }
}

fn cellRuns(cell: ?lc.Value) ?[]const lc.StyleRun {
    const v = cell orelse return null;
    return switch (v) {
        .general => |g| if (g.runs.len > 0) g.runs else null,
        .time => |t| if (t.runs.len > 0) t.runs else null,
        else => null,
    };
}

test "JSON output parses and has expected shape" {
    const testing = std.testing;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();

    var f = try lc.File.init(testing.allocator, testing.io, "test/TESTDB.FOL");
    defer f.deinit();

    try write(testing.allocator, f, &out.writer);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const fields = root.get("fields").?.array;
    try testing.expectEqual(@as(usize, 5), fields.items.len);
    try testing.expectEqualStrings("Bool", fields.items[0].object.get("name").?.string);
    try testing.expectEqualStrings("boolean", fields.items[0].object.get("kind").?.string);

    const records = root.get("records").?.array;
    try testing.expectEqual(@as(usize, 1), records.items.len);
    const rec = records.items[0].object;
    try testing.expectEqual(true, rec.get("Bool").?.bool);
    try testing.expectEqualStrings("1988-10-11", rec.get("Date").?.string);
    try testing.expectEqualStrings("Hello", rec.get("General").?.string);
    try testing.expectEqual(@as(f64, 3.14), rec.get("Numeric").?.float);

    // No styled cells in the fixture -> empty formatting array.
    try testing.expectEqual(@as(usize, 0), root.get("formatting").?.array.items.len);
}
