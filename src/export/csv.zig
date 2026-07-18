//! RFC 4180 CSV exporter. Emits a header row of field names followed by one row
//! per record. Fields are quoted only when they contain a comma, double-quote,
//! CR, or LF; embedded double-quotes are doubled. Line endings are LF. Blank
//! cells become empty fields; there is never a trailing comma.

const std = @import("std");
const lc = @import("lc");
const common = @import("common.zig");

/// Writes `file` as CSV to `writer`. `gpa` backs a small per-cell scratch buffer.
pub fn write(gpa: std.mem.Allocator, file: lc.File, writer: *std.Io.Writer) !void {
    var scratch: std.Io.Writer.Allocating = .init(gpa);
    defer scratch.deinit();

    // Header row: original field names.
    for (file.schema.fields, 0..) |field, i| {
        if (i > 0) try writer.writeByte(',');
        try writeField(writer, field.name);
    }
    try writer.writeByte('\n');

    for (file.records) |record| {
        for (record.cells, 0..) |cell, i| {
            if (i > 0) try writer.writeByte(',');
            if (cell) |v| {
                scratch.clearRetainingCapacity();
                try common.writeValueText(&scratch.writer, v, .yn);
                try writeField(writer, scratch.written());
            }
        }
        try writer.writeByte('\n');
    }
}

/// Writes a single CSV field, quoting and escaping per RFC 4180 as needed.
fn writeField(writer: *std.Io.Writer, text: []const u8) !void {
    if (!needsQuoting(text)) {
        try writer.writeAll(text);
        return;
    }
    try writer.writeByte('"');
    for (text) |ch| {
        if (ch == '"') try writer.writeByte('"');
        try writer.writeByte(ch);
    }
    try writer.writeByte('"');
}

fn needsQuoting(text: []const u8) bool {
    return std.mem.indexOfAny(u8, text, ",\"\r\n") != null;
}

test "CSV quoting edge cases" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    const cases = [_]struct { in: []const u8, want: []const u8 }{
        .{ .in = "plain", .want = "plain" },
        .{ .in = "", .want = "" },
        .{ .in = "a,b", .want = "\"a,b\"" },
        .{ .in = "he said \"hi\"", .want = "\"he said \"\"hi\"\"\"" },
        .{ .in = "line1\nline2", .want = "\"line1\nline2\"" },
        .{ .in = "cr\rhere", .want = "\"cr\rhere\"" },
    };
    for (cases) |case| {
        out.clearRetainingCapacity();
        try writeField(&out.writer, case.in);
        try std.testing.expectEqualStrings(case.want, out.written());
    }
}

test "CSV row shape has no trailing comma" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var f = try lc.File.init(std.testing.allocator, std.testing.io, "test/TESTDB.FOL");
    defer f.deinit();

    try write(std.testing.allocator, f, &out.writer);

    var lines = std.mem.tokenizeScalar(u8, out.written(), '\n');
    const header = lines.next().?;
    try std.testing.expectEqualStrings("Bool,Date,Time,General,Numeric", header);
    const row = lines.next().?;
    try std.testing.expectEqualStrings("Y,1988-10-11,10:11,Hello,3.14", row);
}
