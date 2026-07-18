const std = @import("std");
const LC = @import("lc");

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print("Error: " ++ format ++ "\n" ++ help, args);
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

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();
    const alloc = arena_allocator.allocator();

    var arg_list: std.ArrayList([]const u8) = .empty;
    var arg_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = arg_it.next(); // skip the program name
    while (arg_it.next()) |a| try arg_list.append(alloc, a);
    const args = arg_list.items;

    if (args.len == 0) fatal("No args", .{});

    var filename: ?[]const u8 = null;
    var outfile: ?[]u8 = null;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_file.interface;
    defer stdout_file.flush() catch {};

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
                    stdout_file.flush() catch {};
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

    var f = try LC.File.init(alloc, io, fname);
    defer f.deinit();

    try f.fol.print_records(stdout);

    try stdout.writeAll("\n");
}
