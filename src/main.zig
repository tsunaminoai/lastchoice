const std = @import("std");
const FCF = @import("fcf.zig");

var global_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = global_allocator.allocator();

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    ret: {
        const msg = std.fmt.allocPrint(gpa, format ++ "\n", args) catch break :ret;
        std.io.getStdErr().writeAll(msg) catch {};
    }
    std.process.exit(1);
}

const ArgsIterator = struct {
    args: []const []const u8,
    i: usize = 0,

    fn next(it: *@This()) ?[]const u8 {
        if (it.i >= it.args.len) {
            return null;
        }
        defer it.i += 1;
        return it.args[it.i];
    }

    fn nextOrFatal(it: *@This()) []const u8 {
        return it.next() orelse fatal("expected parameter after {s}", .{it.args[it.i - 1]});
    }
};

pub fn main() anyerror!void {
    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const arg_line = try std.process.argsAlloc(arena);
    const args = arg_line[1..];

    if (args.len == 0) fatal("No args", .{});

    var filename: ?[]const u8 = null;
    var outfile: ?[]u8 = null;
    const PrintMatrix = packed struct {
        header: bool = false,
        form: bool = false,
        records: bool = false,
        csv: bool = false,

        const Int = blk: {
            const bits = @typeInfo(@This()).Struct.fields.len;
            break :blk @Type(.{
                .Int = .{
                    .signedness = .unsigned,
                    .bits = bits,
                },
            });
        };

        fn enableAll() @This() {
            return @as(@This(), @bitCast(~@as(Int, 0)));
        }

        fn isSet(pm: @This()) bool {
            return @as(Int, @bitCast(pm)) == 0;
        }

        fn add(pm: *@This(), other: @This()) void {
            pm.* = @as(@This(), @bitCast(@as(Int, @bitCast(pm.*)) | @as(Int, @bitCast(other))));
        }
    };
    var print_matrix: PrintMatrix = .{};

    var it = ArgsIterator{ .args = args };
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) blk: {
            var i: usize = 1;
            var tmp = PrintMatrix{};
            while (i < arg.len) : (i += 1) switch (arg[i]) {
                'a' => tmp = PrintMatrix.enableAll(),
                'h' => tmp.header = true,
                'c' => tmp.csv = true,
                'r' => tmp.records = true,
                'f' => tmp.form = true,
                'o' => {
                    if (it.next()) |file| {
                        outfile = try arena.alloc(u8, file.len);
                        @memcpy(outfile.?.ptr, file);
                    }
                },
                else => break :blk,
            };
            print_matrix.add(tmp);
            continue;
        } else filename = arg;
    }

    const fname = filename orelse fatal("No input file specificed.", .{});
    const file = try std.fs.cwd().openFile(fname, .{});
    defer file.close();
    const data = try file.readToEndAlloc(arena, std.math.maxInt(u32));

    var f = FCF{ .arena = arena, .data = data };

    f.parse() catch |err| switch (err) {
        error.InvalidMagic => fatal("Invalid FirstChoice database file - Magic number invalid", .{}),
        else => |e| return e,
    };

    const stdout = std.io.getStdOut().writer();

    if (print_matrix.header)
        try f.printHeader(stdout);
    if (print_matrix.form)
        try f.printForm(stdout);
    if (print_matrix.records)
        try f.printRecords(stdout);
    if (print_matrix.csv) {
        var writer = stdout;
        var csvFile: ?std.fs.File = null;
        if (outfile) |o| {
            csvFile = try createOutputFile(o);
            writer = csvFile.?.writer();
        }
        try f.toCSV(writer);
        if (csvFile) |c|
            c.close();
    }
    try stdout.writeAll("\n");
}

pub fn createOutputFile(filename: []const u8) !std.fs.File {
    var outfile: std.fs.File = undefined;
    outfile = std.fs.cwd().openFile(filename, .{
        .mode = .write_only,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            return try std.fs.cwd().createFile(filename, .{
                .truncate = true,
            });
        },
        else => return err,
    };

    std.debug.print("Writing to \"{s}\" ({any})", .{ filename, outfile.mode() });
    return outfile;
}
