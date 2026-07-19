//! Shared helpers for the CSV/JSON/SQLite exporters: safe column-name
//! preparation and value-to-text formatting.

const std = @import("std");
const lc = @import("lc");
const Allocator = std.mem.Allocator;

/// How boolean cells render as text (SQLite stores 0/1 separately and does not
/// use this).
pub const BoolStyle = enum { yn, true_false };

/// Prepares field names for use as SQLite/JSON identifiers/keys, preserving the
/// original order and count (`out.len == fields.len`):
///   * empty (or all-space) names become `field_N` (1-based field index);
///   * case-insensitive duplicates get `_2`, `_3`, ... suffixes.
///
/// The original names are left untouched for the `_fields` fidelity table; only
/// these derived names are used as identifiers/keys. All returned slices are
/// allocated with `a` (an arena is expected).
pub fn prepareColumnNames(a: Allocator, fields: []const lc.FieldDef) ![]const []const u8 {
    const names = try a.alloc([]const u8, fields.len);

    var seen = std.StringHashMap(void).init(a);
    defer seen.deinit();

    for (fields, 0..) |field, i| {
        const trimmed = std.mem.trim(u8, field.name, " ");
        const base = if (trimmed.len == 0)
            try std.fmt.allocPrint(a, "field_{d}", .{i + 1})
        else
            try a.dupe(u8, trimmed);

        var candidate = base;
        var n: usize = 2;
        while (true) {
            const lowered = try std.ascii.allocLowerString(a, candidate);
            if (!seen.contains(lowered)) {
                try seen.put(lowered, {});
                break;
            }
            candidate = try std.fmt.allocPrint(a, "{s}_{d}", .{ base, n });
            n += 1;
        }
        names[i] = candidate;
    }

    return names;
}

/// Writes a value's plain-text representation: general/time as-is, dates as ISO
/// `YYYY-MM-DD`, numerics via the default float format, booleans per `style`.
pub fn writeValueText(writer: *std.Io.Writer, v: lc.Value, style: BoolStyle) !void {
    switch (v) {
        .general => |g| try writer.writeAll(g.text),
        .time => |t| try writer.writeAll(t.text),
        .numeric => |num| try writer.print("{d}", .{num}),
        .date => |d| try d.writeIso(writer),
        .boolean => |b| switch (style) {
            .yn => try writer.writeAll(if (b) "Y" else "N"),
            .true_false => try writer.writeAll(if (b) "true" else "false"),
        },
    }
}

test "prepareColumnNames rewrites blanks and dedups case-insensitively" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fields = [_]lc.FieldDef{
        .{ .name = "Name", .kind = .general },
        .{ .name = "name", .kind = .general },
        .{ .name = "   ", .kind = .general },
        .{ .name = "Name", .kind = .general },
    };
    const names = try prepareColumnNames(a, &fields);
    try std.testing.expectEqual(@as(usize, 4), names.len);
    try std.testing.expectEqualStrings("Name", names[0]);
    try std.testing.expectEqualStrings("name_2", names[1]);
    try std.testing.expectEqualStrings("field_3", names[2]);
    try std.testing.expectEqualStrings("Name_3", names[3]);
}
