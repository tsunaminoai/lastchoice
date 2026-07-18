//! LastChoice CLI: inspect and dump FirstChoice `.FOL` databases.
//!
//!   lastchoice info  FILE.FOL                 header + schema summary
//!   lastchoice print FILE.FOL                 record table to stdout
//!   lastchoice dump  FILE.FOL [-o OUT] [--sqlite|--csv|--json]
//!
//! `dump` defaults to SQLite, writing `<basename>.db`. `--csv`/`--json` write to
//! stdout unless `-o` is given; with `-o` and no explicit format the format is
//! inferred from the output extension.

const std = @import("std");
const lc = @import("lc");

const csv = @import("export/csv.zig");
const json = @import("export/json.zig");
const sqlite = @import("export/sqlite.zig");

const usage =
    \\lastchoice - inspect and dump FirstChoice .FOL databases
    \\
    \\Usage:
    \\  lastchoice info  FILE.FOL                  Print header and schema summary
    \\  lastchoice print FILE.FOL                  Print the record table to stdout
    \\  lastchoice dump  FILE.FOL [options]        Export records
    \\
    \\Dump options:
    \\  -o OUT            Write to OUT instead of the default/stdout
    \\  --sqlite         Export to a SQLite database (default; OUT defaults to <name>.db)
    \\  --csv            Export as CSV (to stdout unless -o given)
    \\  --json           Export as JSON (to stdout unless -o given)
    \\
    \\With -o and no explicit format, the format is inferred from the extension
    \\(.db/.sqlite/.sqlite3 -> sqlite, .csv -> csv, .json -> json).
    \\
;

const Format = enum { sqlite, csv, json };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var arg_list: std.ArrayList([]const u8) = .empty;
    var arg_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = arg_it.next(); // skip program name
    while (arg_it.next()) |a| try arg_list.append(arena, a);
    const args = arg_list.items;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_file.interface;
    defer stdout_file.flush() catch {};

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_file.interface;
    defer stderr_file.flush() catch {};

    if (args.len == 0) {
        try stderr.writeAll(usage);
        stderr_file.flush() catch {};
        std.process.exit(1);
    }
    if (isHelp(args[0])) {
        try stdout.writeAll(usage);
        return;
    }

    const command = args[0];
    const rest = args[1..];

    if (std.mem.eql(u8, command, "info")) {
        try runInfo(gpa, arena, io, rest, stdout, stderr);
    } else if (std.mem.eql(u8, command, "print")) {
        try runPrint(gpa, io, rest, stdout, stderr);
    } else if (std.mem.eql(u8, command, "dump")) {
        try runDump(gpa, arena, io, rest, stdout, stderr);
    } else {
        try stderr.print("unknown command '{s}'\n\n", .{command});
        try stderr.writeAll(usage);
        stderr_file.flush() catch {};
        std.process.exit(1);
    }
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help");
}

fn fail(stderr: *std.Io.Writer, comptime fmt: []const u8, fmt_args: anytype) noreturn {
    stderr.print("error: " ++ fmt ++ "\n", fmt_args) catch {};
    stderr.flush() catch {};
    std.process.exit(1);
}

fn requireFile(rest: []const []const u8, stderr: *std.Io.Writer) []const u8 {
    if (rest.len == 0) fail(stderr, "expected a FILE.FOL argument", .{});
    return rest[0];
}

fn runInfo(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    rest: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    _ = arena;
    const path = requireFile(rest, stderr);
    var f = try lc.File.init(gpa, io, path);
    defer f.deinit();

    try stdout.print("File: {s}\n", .{path});
    try stdout.print("Records: {d}\n", .{f.records.len});
    try stdout.print("Fields: {d}\n", .{f.schema.fields.len});
    try stdout.writeAll("\nSchema:\n");
    for (f.schema.fields, 0..) |field, i| {
        try stdout.print("  [{d}] {s} ({s})\n", .{ i, field.name, @tagName(field.kind) });
    }
}

fn runPrint(
    gpa: std.mem.Allocator,
    io: std.Io,
    rest: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    const path = requireFile(rest, stderr);
    var f = try lc.File.init(gpa, io, path);
    defer f.deinit();
    try f.print(stdout);
}

fn runDump(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    rest: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    var path: ?[]const u8 = null;
    var outfile: ?[]const u8 = null;
    var format: ?Format = null;

    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        const arg = rest[i];
        if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= rest.len) fail(stderr, "-o requires an output path", .{});
            outfile = rest[i];
        } else if (std.mem.eql(u8, arg, "--sqlite")) {
            format = .sqlite;
        } else if (std.mem.eql(u8, arg, "--csv")) {
            format = .csv;
        } else if (std.mem.eql(u8, arg, "--json")) {
            format = .json;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            fail(stderr, "unknown dump option '{s}'", .{arg});
        } else {
            if (path != null) fail(stderr, "unexpected extra argument '{s}'", .{arg});
            path = arg;
        }
    }

    const fol_path = path orelse fail(stderr, "expected a FILE.FOL argument", .{});

    // Resolve format: explicit flag > inferred from -o extension > sqlite.
    const fmt = format orelse if (outfile) |o| inferFormat(o) orelse .sqlite else .sqlite;

    var f = try lc.File.init(gpa, io, fol_path);
    defer f.deinit();

    switch (fmt) {
        .sqlite => {
            const out = outfile orelse try defaultDbName(arena, fol_path);
            try sqlite.write(gpa, io, f, out);
            try stdout.print("Wrote {d} records to {s}\n", .{ f.records.len, out });
        },
        .csv, .json => {
            if (outfile) |o| {
                var file = try std.Io.Dir.cwd().createFile(io, o, .{});
                defer file.close(io);
                var buf: [4096]u8 = undefined;
                var fw = file.writer(io, &buf);
                if (fmt == .csv) {
                    try csv.write(gpa, f, &fw.interface);
                } else {
                    try json.write(gpa, f, &fw.interface);
                }
                try fw.interface.flush();
                try stdout.print("Wrote {d} records to {s}\n", .{ f.records.len, o });
            } else {
                if (fmt == .csv) {
                    try csv.write(gpa, f, stdout);
                } else {
                    try json.write(gpa, f, stdout);
                }
            }
        },
    }
}

fn inferFormat(path: []const u8) ?Format {
    const ext = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(ext, ".db") or
        std.ascii.eqlIgnoreCase(ext, ".sqlite") or
        std.ascii.eqlIgnoreCase(ext, ".sqlite3")) return .sqlite;
    if (std.ascii.eqlIgnoreCase(ext, ".csv")) return .csv;
    if (std.ascii.eqlIgnoreCase(ext, ".json")) return .json;
    return null;
}

/// `<basename-without-extension>.db` in the current directory.
fn defaultDbName(arena: std.mem.Allocator, fol_path: []const u8) ![]const u8 {
    const base = std.fs.path.basename(fol_path);
    const ext = std.fs.path.extension(base);
    const stem = base[0 .. base.len - ext.len];
    return std.fmt.allocPrint(arena, "{s}.db", .{stem});
}

test {
    _ = csv;
    _ = json;
    _ = sqlite;
    _ = @import("export/common.zig");
}

test "inferFormat by extension" {
    try std.testing.expectEqual(Format.sqlite, inferFormat("out.db").?);
    try std.testing.expectEqual(Format.sqlite, inferFormat("out.sqlite3").?);
    try std.testing.expectEqual(Format.csv, inferFormat("out.CSV").?);
    try std.testing.expectEqual(Format.json, inferFormat("out.json").?);
    try std.testing.expectEqual(@as(?Format, null), inferFormat("out.txt"));
}

test "defaultDbName strips path and extension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const name = try defaultDbName(arena.allocator(), "test/TESTDB.FOL");
    try std.testing.expectEqualStrings("TESTDB.db", name);
}
