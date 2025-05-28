const std = @import("std");
const LC = @import("lc");

var global_allocator = std.heap.DebugAllocator(.{}){};
var gpa = global_allocator.allocator();

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    ret: {
        const msg = std.fmt.allocPrint(
            gpa,
            "Error: " ++ format ++ "\n" ++ help,
            args,
        ) catch break :ret;
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
        return it.next() orelse fatal(
            "expected parameter after {s}",
            .{it.args[it.i - 1]},
        );
    }
};

const help =
    \\
    \\ Usage: lastchoice (OPTIONS) FirstChoiceDB.FOL
    \\
    \\ By default, without specifiying options, the program will only read in and parse the input FOL file, failing if it cannot.
    \\
    \\ Options:
    \\   -h | Show this help
    \\   -a | Print the header and form information as well as the entirity of the records to stdout
    \\   -d | Print the database header information (db file info)
    \\   -f | Print the database form information (db schema)
    \\   -r | Print the records to std out
    \\   -c | Format file output as csv
    \\   -o  <filename.ext> | Save the output to a file with format elsewhere specified
    \\
;

pub fn main() anyerror!void {
    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();
    const alloc = arena_allocator.allocator();

    const arg_line = try std.process.argsAlloc(alloc);
    const args = arg_line[1..];

    if (args.len == 0) fatal("No args", .{});

    var filename: ?[]const u8 = null;
    var outfile: ?[]u8 = null;
    const stdout = std.io.getStdOut().writer();

    const Options = packed struct(u4) {
        header: bool = false,
        form: bool = false,
        records: bool = false,
        csv: bool = false,
        const Opt = @This();

        pub fn enableAll() Opt {
            return .{
                .header = true,
                .form = true,
                .records = true,
                .csv = true,
            };
        }
        pub fn add(self: Opt, other: Opt) Opt {
            return @bitCast(@as(u4, @bitCast(self)) | @as(u4, @bitCast(other)));
        }
    };
    var options = Options{};

    var it = ArgsIterator{ .args = args };
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) blk: {
            var i: usize = 1;
            var tmp = Options{};
            while (i < arg.len) : (i += 1) switch (arg[i]) {
                'a' => tmp = Options.enableAll(),
                'h' => {
                    try stdout.print(help ++ "\n", .{});
                    std.process.exit(0);
                },
                'd' => tmp.header = true,
                'c' => tmp.csv = true,
                'r' => tmp.records = true,
                'f' => tmp.form = true,
                'o' => {
                    if (it.next()) |file| {
                        outfile = try alloc.alloc(u8, file.len);
                        @memcpy(outfile.?.ptr, file);
                    }
                },
                else => break :blk,
            };
            options = options.add(tmp);
            continue;
        } else filename = arg;
    }

    const fname = filename orelse fatal(
        "No input file specificed.",
        .{},
    );
    // const file = try std.fs.cwd().openFile(fname, .{});
    // defer file.close();
    // const data = try file.readToEndAlloc(
    //     alloc,
    //     std.math.maxInt(u32),
    // );

    var f = try LC.File.init(alloc, fname);
    defer f.deinit();

    // std.debug.print("{any}\n", .{f.fol.header});
    // for (f.fol.blocks) |b| {
    //     std.debug.print("{}\n", .{b});
    //     if (b.type == .FormDescriptionView) {
    //         std.debug.print("{}\n", .{b.data.Schema});
    //     }
    // }
    // std.debug.print("{any}\n", .{f.fol.blocks[f.fol.header.schemaPosition()].data.Schema});

    // var f = FCF{ .arena = arena_allocator, .data = data };

    // f.parse() catch |err| switch (err) {
    //     error.InvalidMagic => fatal(
    //         "Invalid FirstChoice database file - Magic number invalid",
    //         .{},
    //     ),
    //     else => |e| return e,
    // };

    // if (options.header)
    //     try f.printHeader(stdout);
    // if (options.form)
    //     try f.printForm(stdout);
    // if (options.records)
    //     try f.printRecords(stdout);
    // if (options.csv) {
    //     var writer = stdout;
    //     var csvFile: ?std.fs.File = null;
    //     if (outfile) |o| {
    //         csvFile = try createOutputFile(o);
    //         writer = csvFile.?.writer();
    //     }
    //     try f.toCSV(writer);
    //     if (csvFile) |c|
    //         c.close();
    // }
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

    std.debug.print(
        "Writing to \"{s}\" ({any})",
        .{ filename, outfile.mode() },
    );
    return outfile;
}
