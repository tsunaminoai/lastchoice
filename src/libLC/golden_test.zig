//! Golden tests over the two bundled fixtures. Literals were derived by running
//! the parser and cross-checking against a hex dump of each file.

const std = @import("std");
const lc = @import("liblc.zig");

fn expectGeneral(cell: ?lc.Value, text: []const u8) !void {
    try std.testing.expect(cell != null);
    try std.testing.expectEqualStrings(text, cell.?.general.text);
}

fn expectNumeric(cell: ?lc.Value, n: f64) !void {
    try std.testing.expect(cell != null);
    try std.testing.expectEqual(n, cell.?.numeric);
}

fn expectDate(cell: ?lc.Value, d: lc.Date) !void {
    try std.testing.expect(cell != null);
    try std.testing.expectEqual(d, cell.?.date);
}

test "TESTDB.FOL golden" {
    var f = try lc.File.init(std.testing.allocator, std.testing.io, "test/TESTDB.FOL");
    defer f.deinit();

    // Schema: five fields, one of each kind.
    const names = [_][]const u8{ "Bool", "Date", "Time", "General", "Numeric" };
    const kinds = [_]lc.Kind{ .boolean, .date, .time, .general, .numeric };
    try std.testing.expectEqual(names.len, f.schema.fields.len);
    for (f.schema.fields, names, kinds) |field, name, kind| {
        try std.testing.expectEqualStrings(name, field.name);
        try std.testing.expectEqual(kind, field.kind);
    }

    // A single record: Y | 10/11/88 | 10:11 | Hello | 3.14
    try std.testing.expectEqual(@as(usize, 1), f.records.len);
    const cells = f.records[0].cells;
    try std.testing.expectEqual(f.schema.fields.len, cells.len);

    try std.testing.expectEqual(true, cells[0].?.boolean);
    try expectDate(cells[1], .{ .year = 1988, .month = 10, .day = 11 });
    try std.testing.expectEqualStrings("10:11", cells[2].?.time.text);
    try expectGeneral(cells[3], "Hello");
    try expectNumeric(cells[4], 3.14);

    // No fixture cell carries formatting, so the "Hello" run list is empty.
    try std.testing.expectEqual(@as(usize, 0), cells[3].?.general.runs.len);
}

test "RESERVE.FOL golden" {
    var f = try lc.File.init(std.testing.allocator, std.testing.io, "RESERVE.FOL");
    defer f.deinit();

    // Schema: thirteen fields.
    const names = [_][]const u8{
        "First name",            "Last name",      "Address",
        "City",                  "State",          "Zip",
        "Date reservation made", "Date of flight", "Number in party",
        "Balloon name",          "Pilot name",     "Amount of deposit",
        "Balance",
    };
    const kinds = [_]lc.Kind{
        .general, .general, .general, .general, .general, .general,
        .date,    .date,    .general, .general, .general, .numeric,
        .numeric,
    };
    try std.testing.expectEqual(names.len, f.schema.fields.len);
    for (f.schema.fields, names, kinds) |field, name, kind| {
        try std.testing.expectEqualStrings(name, field.name);
        try std.testing.expectEqual(kind, field.kind);
    }

    // Eight records, each fully padded to the schema width.
    try std.testing.expectEqual(@as(usize, 8), f.records.len);
    for (f.records) |record| {
        try std.testing.expectEqual(f.schema.fields.len, record.cells.len);
    }

    // Record 0: Chuck Coleman.
    const r0 = f.records[0].cells;
    try expectGeneral(r0[0], "Chuck");
    try expectGeneral(r0[1], "Coleman");
    try expectGeneral(r0[2], "14006 Flamingo");
    try expectGeneral(r0[3], "Miami");
    try expectGeneral(r0[4], "FL");
    try expectGeneral(r0[5], "20731");
    try expectDate(r0[6], .{ .year = 1988, .month = 8, .day = 27 }); // spans a continuation block
    try expectDate(r0[7], .{ .year = 1988, .month = 10, .day = 18 });
    try expectGeneral(r0[8], "1");
    try expectGeneral(r0[9], "Basket Case");
    try expectGeneral(r0[10], "Ruth"); // "Ruth\r\r\r": odd carriage-return run
    try expectNumeric(r0[11], 70.0); // "$70.00": currency-stripped
    try expectNumeric(r0[12], 50.0);

    // Record 2: a $0 balance (short numeric text).
    const r2 = f.records[2].cells;
    try expectGeneral(r2[0], "Jason");
    try expectNumeric(r2[11], 120.0);
    try expectNumeric(r2[12], 0.0);

    // Record 7: last row.
    const r7 = f.records[7].cells;
    try expectGeneral(r7[0], "Julia");
    try expectGeneral(r7[1], "Carpentier");
    try expectGeneral(r7[3], "San Francisco");
    try expectDate(r7[7], .{ .year = 1988, .month = 11, .day = 20 });
    try expectNumeric(r7[12], 140.0);

    // Formatting: none of the record cells are styled in this fixture.
    try std.testing.expectEqual(@as(usize, 0), r0[9].?.general.runs.len);
}
