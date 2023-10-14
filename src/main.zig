const std = @import("std");
const FCF = @import("firstzig");

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

    // TODO: add actual options

    var it = ArgsIterator{ .args = args };
    while (it.next()) |arg| {
        filename = arg;
    }

    const file = try std.fs.cwd().openFile(filename.?, .{});
    defer file.close();
    const data = try file.readToEndAlloc(arena, std.math.maxInt(u32));

    var f = FCF{ .arena = arena, .data = data };

    f.parse() catch |err| switch (err) {
        error.InvalidMagic => fatal("Invalid FirstChoice database file - Magic number invalid", .{}),
        else => |e| return e,
    };

    const stdout = std.io.getStdOut().writer();

    try f.printHeader(stdout);
    try f.printForm(stdout);
    try f.printRecords(stdout);
    try stdout.writeAll("\n");
}
