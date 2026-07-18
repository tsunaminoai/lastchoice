//! Typed value model for parsed FirstChoice records.
//!
//! Everything here is intended to be arena-owned by the owning `File`: slices
//! point into the file's arena and must not be freed individually.

const std = @import("std");

/// The kind of a schema field. The integer tags match the on-disk field-type
/// markers stored in the low nibble of a schema field's terminating byte.
pub const Kind = enum(u8) {
    general = 1,
    numeric = 2,
    date = 3,
    time = 4,
    boolean = 5,

    pub fn fromInt(value: u8) ?Kind {
        if (value < 1 or value > 5) return null;
        return @enumFromInt(value);
    }
};

/// Character-level formatting flags, packed for a compact 1:1 mapping onto the
/// SQLite `_formatting` sidecar and vaxis styled segments.
pub const Style = packed struct(u8) {
    bold: bool = false,
    underline: bool = false,
    italic: bool = false,
    background: bool = false,
    /// Set when the character originated from a form field/label marker rather
    /// than record data. Only ever appears in schema text, never record cells.
    field: bool = false,
    _padding: u3 = 0,

    pub fn isDefault(self: Style) bool {
        return @as(u8, @bitCast(self)) == 0;
    }

    pub fn eql(a: Style, b: Style) bool {
        return @as(u8, @bitCast(a)) == @as(u8, @bitCast(b));
    }
};

/// A run-length-encoded span of styled characters within a `StyledText`.
///
/// `start`/`len` are byte offsets/lengths into the associated text. Only
/// non-default runs are ever materialised; the absence of a run means default
/// (unstyled) formatting.
pub const StyleRun = struct {
    start: u32,
    len: u32,
    style: Style,
    /// The raw FOL attribute/marker byte this run was decoded from, preserved
    /// verbatim so that no formatting information is lost even where the exact
    /// bit semantics are not yet confirmed.
    /// TODO(zig-0.16-migration): confirm bold/underline/italic bit semantics of
    /// the 0xC0-0xCF / 0xD0-0xDF marker bytes against a fixture that actually
    /// contains styled record text (neither TESTDB.FOL nor RESERVE.FOL does).
    marker: u8 = 0,
};

/// Text plus its formatting runs. `runs` is empty for wholly-unstyled text.
pub const StyledText = struct {
    text: []const u8,
    runs: []const StyleRun = &.{},
};

/// A calendar date. Time-of-day is not represented here; see `Kind.time`.
pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn writeIso(self: Date, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }
};

/// A single typed cell value. Blank cells are represented by `?Value` being
/// null at the `Record` level, never by a variant here.
pub const Value = union(Kind) {
    general: StyledText,
    numeric: f64,
    date: Date,
    /// Time-of-day encoding is not understood, so the raw display text is kept.
    /// TODO(zig-0.16-migration): decode the time field encoding.
    time: StyledText,
    boolean: bool,

    pub fn format(self: Value, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .general => |g| try writer.writeAll(g.text),
            .numeric => |n| try writer.print("{d}", .{n}),
            .time => |t| try writer.writeAll(t.text),
            .date => |d| try d.writeIso(writer),
            .boolean => |b| try writer.writeAll(if (b) "Y" else "N"),
        }
    }
};

/// A record is exactly `Schema.fields.len` cells; a null cell is blank.
pub const Record = struct {
    cells: []const ?Value,
};

/// Parses a date in the FirstChoice "MM/DD/YY" display form. The two-digit year
/// is expanded with a Y2K pivot at 70 (00-69 -> 2000-2069, 70-99 -> 1970-1999).
pub fn parseDate(text: []const u8) !Date {
    const trimmed = std.mem.trim(u8, text, " ");
    if (trimmed.len < 8) return error.InvalidDate;
    const month = try std.fmt.parseInt(u8, trimmed[0..2], 10);
    const day = try std.fmt.parseInt(u8, trimmed[3..5], 10);
    var year: u16 = try std.fmt.parseInt(u16, trimmed[6..8], 10);
    if (year < 70) {
        year += 2000;
    } else {
        year += 1900;
    }
    return .{ .year = year, .month = month, .day = day };
}

/// Parses a numeric cell, tolerating the currency/grouping decoration
/// FirstChoice stores for money-formatted fields (e.g. "$70.00", "1,200").
pub fn parseNumeric(text: []const u8) !f64 {
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    for (text) |c| {
        switch (c) {
            '$', ',', ' ' => {},
            else => {
                if (n >= buf.len) return error.NumberTooLong;
                buf[n] = c;
                n += 1;
            },
        }
    }
    if (n == 0) return error.EmptyNumber;
    return std.fmt.parseFloat(f64, buf[0..n]);
}

test "parseDate y2k pivot" {
    try std.testing.expectEqual(Date{ .year = 1988, .month = 10, .day = 11 }, try parseDate("10/11/88"));
    try std.testing.expectEqual(Date{ .year = 2005, .month = 1, .day = 2 }, try parseDate("01/02/05"));
}

test "parseNumeric strips currency" {
    try std.testing.expectEqual(@as(f64, 3.14), try parseNumeric("3.14"));
    try std.testing.expectEqual(@as(f64, 70.0), try parseNumeric("$70.00"));
    try std.testing.expectEqual(@as(f64, 1200.0), try parseNumeric("$1,200"));
    try std.testing.expectError(error.EmptyNumber, parseNumeric(""));
}
