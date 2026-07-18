//! SQLite exporter. Writes a fresh single-writer dump of an `lc.File` to a
//! `.db` file using the raw SQLite C API (bundled/compiled by zig-sqlite).
//!
//! Layout:
//!   * `records(id INTEGER PRIMARY KEY, "<col>" <type>, ...)` — one row per
//!     record; Numeric->REAL, Bool->INTEGER (0/1), General/Date/Time->TEXT
//!     (dates ISO `YYYY-MM-DD`), blank cells->NULL.
//!   * `_fields(idx INTEGER PRIMARY KEY, name TEXT, kind TEXT)` — original field
//!     names/kinds, in schema order (idx is the 0-based field index).
//!   * `_formatting(record_id, field_idx, start, len, bold, underline, italic,
//!     background)` — one row per non-default style run.
//!
//! Identifiers are always double-quoted with `""` escaping; column names come
//! from `common.prepareColumnNames` (blanks -> field_N, dupes -> _2/_3).

const std = @import("std");
const lc = @import("lc");
const common = @import("common.zig");
const c = @import("sqlite").c;

pub const Error = error{Sqlite} || std.mem.Allocator.Error;

/// Dumps `file` to a SQLite database at `path`, overwriting any existing file.
pub fn write(gpa: std.mem.Allocator, io: std.Io, file: lc.File, path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    // Fresh dump: remove any prior output so we never append to stale schema.
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const path_z = try a.dupeZ(u8, path);
    var db: ?*c.sqlite3 = null;
    if (c.sqlite3_open_v2(path_z.ptr, &db, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE, null) != c.SQLITE_OK) {
        std.log.err("sqlite: cannot open '{s}': {s}", .{ path, errmsg(db) });
        _ = c.sqlite3_close(db);
        return error.Sqlite;
    }
    defer _ = c.sqlite3_close(db);

    // Single-writer bulk load: skip journaling/sync entirely.
    try exec(db, "PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA locking_mode=EXCLUSIVE;");

    const cols = try common.prepareColumnNames(a, file.schema.fields);

    try createTables(a, db, file, cols);

    try exec(db, "BEGIN");
    try insertFields(db, file);
    try insertRecords(a, db, file, cols);
    try insertFormatting(db, file);
    try exec(db, "COMMIT");
}

fn createTables(a: std.mem.Allocator, db: ?*c.sqlite3, file: lc.File, cols: []const []const u8) !void {
    var sql: std.Io.Writer.Allocating = .init(a);
    defer sql.deinit();
    const w = &sql.writer;

    try w.writeAll("CREATE TABLE records(id INTEGER PRIMARY KEY");
    for (file.schema.fields, cols) |field, name| {
        try w.writeAll(", ");
        try writeIdent(w, name);
        try w.writeByte(' ');
        try w.writeAll(sqlType(field.kind));
    }
    try w.writeByte(')');
    try execZ(a, db, sql.written());

    try exec(db, "CREATE TABLE _fields(idx INTEGER PRIMARY KEY, name TEXT, kind TEXT)");
    try exec(db,
        \\CREATE TABLE _formatting(
        \\  record_id INTEGER, field_idx INTEGER, start INTEGER, len INTEGER,
        \\  bold INTEGER, underline INTEGER, italic INTEGER, background INTEGER)
    );
}

fn insertFields(db: ?*c.sqlite3, file: lc.File) !void {
    const stmt = try prepare(db, "INSERT INTO _fields(idx, name, kind) VALUES(?,?,?)");
    defer _ = c.sqlite3_finalize(stmt);
    for (file.schema.fields, 0..) |field, i| {
        try reset(db, stmt);
        try bindInt(db, stmt, 1, @intCast(i));
        try bindText(db, stmt, 2, field.name);
        try bindText(db, stmt, 3, @tagName(field.kind));
        try stepDone(db, stmt);
    }
}

fn insertRecords(a: std.mem.Allocator, db: ?*c.sqlite3, file: lc.File, cols: []const []const u8) !void {
    var sql: std.Io.Writer.Allocating = .init(a);
    defer sql.deinit();
    const w = &sql.writer;

    try w.writeAll("INSERT INTO records(id");
    for (cols) |name| {
        try w.writeAll(", ");
        try writeIdent(w, name);
    }
    try w.writeAll(") VALUES(?");
    for (cols) |_| try w.writeAll(",?");
    try w.writeByte(')');

    const stmt = try prepareZ(a, db, sql.written());
    defer _ = c.sqlite3_finalize(stmt);

    var scratch: std.Io.Writer.Allocating = .init(a);
    defer scratch.deinit();

    for (file.records, 0..) |record, r| {
        try reset(db, stmt);
        try bindInt(db, stmt, 1, @intCast(r));
        for (record.cells, 0..) |cell, i| {
            const idx: c_int = @intCast(i + 2); // column 1 is id
            const v = cell orelse {
                try bindNull(db, stmt, idx);
                continue;
            };
            switch (v) {
                .numeric => |num| try bindDouble(db, stmt, idx, num),
                .boolean => |b| try bindInt(db, stmt, idx, if (b) 1 else 0),
                .general => |g| try bindText(db, stmt, idx, g.text),
                .time => |t| try bindText(db, stmt, idx, t.text),
                .date => |d| {
                    scratch.clearRetainingCapacity();
                    try d.writeIso(&scratch.writer);
                    try bindText(db, stmt, idx, scratch.written());
                },
            }
        }
        try stepDone(db, stmt);
    }
}

fn insertFormatting(db: ?*c.sqlite3, file: lc.File) !void {
    const stmt = try prepare(db,
        \\INSERT INTO _formatting(record_id, field_idx, start, len, bold, underline, italic, background)
        \\VALUES(?,?,?,?,?,?,?,?)
    );
    defer _ = c.sqlite3_finalize(stmt);

    for (file.records, 0..) |record, r| {
        for (record.cells, 0..) |cell, fld| {
            const runs = cellRuns(cell) orelse continue;
            for (runs) |run| {
                try reset(db, stmt);
                try bindInt(db, stmt, 1, @intCast(r));
                try bindInt(db, stmt, 2, @intCast(fld));
                try bindInt(db, stmt, 3, run.start);
                try bindInt(db, stmt, 4, run.len);
                try bindInt(db, stmt, 5, @intFromBool(run.style.bold));
                try bindInt(db, stmt, 6, @intFromBool(run.style.underline));
                try bindInt(db, stmt, 7, @intFromBool(run.style.italic));
                try bindInt(db, stmt, 8, @intFromBool(run.style.background));
                try stepDone(db, stmt);
            }
        }
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

fn sqlType(kind: lc.Kind) []const u8 {
    return switch (kind) {
        .numeric => "REAL",
        .boolean => "INTEGER",
        .general, .date, .time => "TEXT",
    };
}

/// Writes a double-quoted SQL identifier, escaping embedded `"` as `""`.
fn writeIdent(w: *std.Io.Writer, name: []const u8) !void {
    try w.writeByte('"');
    for (name) |ch| {
        if (ch == '"') try w.writeByte('"');
        try w.writeByte(ch);
    }
    try w.writeByte('"');
}

// --- thin C-API helpers -----------------------------------------------------

fn errmsg(db: ?*c.sqlite3) []const u8 {
    return std.mem.span(c.sqlite3_errmsg(db));
}

fn exec(db: ?*c.sqlite3, sql: [:0]const u8) !void {
    if (c.sqlite3_exec(db, sql.ptr, null, null, null) != c.SQLITE_OK) {
        std.log.err("sqlite exec failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
}

fn execZ(a: std.mem.Allocator, db: ?*c.sqlite3, sql: []const u8) !void {
    const z = try a.dupeZ(u8, sql);
    if (c.sqlite3_exec(db, z.ptr, null, null, null) != c.SQLITE_OK) {
        std.log.err("sqlite exec failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
}

fn prepare(db: ?*c.sqlite3, sql: [:0]const u8) !?*c.sqlite3_stmt {
    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, sql.ptr, @intCast(sql.len), &stmt, null) != c.SQLITE_OK) {
        std.log.err("sqlite prepare failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
    return stmt;
}

fn prepareZ(a: std.mem.Allocator, db: ?*c.sqlite3, sql: []const u8) !?*c.sqlite3_stmt {
    const z = try a.dupeZ(u8, sql);
    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, z.ptr, @intCast(z.len), &stmt, null) != c.SQLITE_OK) {
        std.log.err("sqlite prepare failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
    return stmt;
}

fn reset(db: ?*c.sqlite3, stmt: ?*c.sqlite3_stmt) !void {
    if (c.sqlite3_reset(stmt) != c.SQLITE_OK) {
        std.log.err("sqlite reset failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
    _ = c.sqlite3_clear_bindings(stmt);
}

fn stepDone(db: ?*c.sqlite3, stmt: ?*c.sqlite3_stmt) !void {
    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
        std.log.err("sqlite step failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
}

fn bindInt(db: ?*c.sqlite3, stmt: ?*c.sqlite3_stmt, idx: c_int, v: i64) !void {
    if (c.sqlite3_bind_int64(stmt, idx, v) != c.SQLITE_OK) {
        std.log.err("sqlite bind failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
}

fn bindDouble(db: ?*c.sqlite3, stmt: ?*c.sqlite3_stmt, idx: c_int, v: f64) !void {
    if (c.sqlite3_bind_double(stmt, idx, v) != c.SQLITE_OK) {
        std.log.err("sqlite bind failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
}

fn bindText(db: ?*c.sqlite3, stmt: ?*c.sqlite3_stmt, idx: c_int, text: []const u8) !void {
    // SQLITE_TRANSIENT: SQLite copies the bytes immediately, so reused scratch
    // buffers are safe.
    if (c.sqlite3_bind_text(stmt, idx, text.ptr, @intCast(text.len), c.sqliteTransientAsDestructor()) != c.SQLITE_OK) {
        std.log.err("sqlite bind failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
}

fn bindNull(db: ?*c.sqlite3, stmt: ?*c.sqlite3_stmt, idx: c_int) !void {
    if (c.sqlite3_bind_null(stmt, idx) != c.SQLITE_OK) {
        std.log.err("sqlite bind failed: {s}", .{errmsg(db)});
        return error.Sqlite;
    }
}

test "SQLite end-to-end dump and reopen" {
    const testing = std.testing;
    const sqlite = @import("sqlite");

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    // The tmp dir lives under .zig-cache/tmp relative to the test cwd (repo root).
    const out_path = try std.fmt.allocPrintSentinel(testing.allocator, ".zig-cache/tmp/{s}/testdb.db", .{tmp.sub_path}, 0);
    defer testing.allocator.free(out_path);

    {
        var f = try lc.File.init(testing.allocator, testing.io, "test/TESTDB.FOL");
        defer f.deinit();
        try write(testing.allocator, testing.io, f, out_path);
    }

    var db = try sqlite.Db.init(.{
        .mode = .{ .File = out_path },
        .open_flags = .{ .write = true },
    });
    defer db.deinit();

    const records = try db.one(usize, "SELECT count(*) FROM records", .{}, .{});
    try testing.expectEqual(@as(usize, 1), records.?);
    const fields = try db.one(usize, "SELECT count(*) FROM _fields", .{}, .{});
    try testing.expectEqual(@as(usize, 5), fields.?);

    // Typed round-trip of a couple of cells.
    const general = try db.oneAlloc([]const u8, testing.allocator, "SELECT \"General\" FROM records WHERE id=0", .{}, .{});
    defer if (general) |g| testing.allocator.free(g);
    try testing.expectEqualStrings("Hello", general.?);
    const numeric = try db.one(f64, "SELECT \"Numeric\" FROM records WHERE id=0", .{}, .{});
    try testing.expectEqual(@as(f64, 3.14), numeric.?);
    const date = try db.oneAlloc([]const u8, testing.allocator, "SELECT \"Date\" FROM records WHERE id=0", .{}, .{});
    defer if (date) |d| testing.allocator.free(d);
    try testing.expectEqualStrings("1988-10-11", date.?);
}

test "SQLite dump of RESERVE.FOL has 8 records" {
    const testing = std.testing;
    const sqlite = @import("sqlite");

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const out_path = try std.fmt.allocPrintSentinel(testing.allocator, ".zig-cache/tmp/{s}/reserve.db", .{tmp.sub_path}, 0);
    defer testing.allocator.free(out_path);

    {
        var f = try lc.File.init(testing.allocator, testing.io, "RESERVE.FOL");
        defer f.deinit();
        try write(testing.allocator, testing.io, f, out_path);
    }

    var db = try sqlite.Db.init(.{
        .mode = .{ .File = out_path },
        .open_flags = .{ .write = true },
    });
    defer db.deinit();

    const records = try db.one(usize, "SELECT count(*) FROM records", .{}, .{});
    try testing.expectEqual(@as(usize, 8), records.?);
    const fields = try db.one(usize, "SELECT count(*) FROM _fields", .{}, .{});
    try testing.expectEqual(@as(usize, 13), fields.?);
}
