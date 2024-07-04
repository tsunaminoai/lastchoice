const std = @import("std");
const Blocks = @import("blocks.zig");
const Schema = @import("schema.zig");
const Records = @import("record.zig");
const FOL = @import("fol.zig");
const LCFile = FOL;

var raw: []u8 = undefined;
var alloc: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !*LCFile {
    const self = try allocator.create(LCFile);
    errdefer allocator.destroy(self);

    alloc = allocator;
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    raw = try file.readToEndAlloc(
        alloc,
        std.math.maxInt(u32),
    );
    errdefer alloc.free(raw);
    self.* = FOL.init(raw);
    errdefer self.deinit();

    return self;
}

pub fn deinit(self: *LCFile) void {
    // self.schema.deinit();
    alloc.free(raw);
    alloc.destroy(self);
}

test "LCFile" {
    const allocator = std.testing.allocator;
    const file = try init(allocator, "test/TESTDB.FOL");
    defer deinit(file);

    // try std.testing.expectEqual(raw.len, file.header.totalFileBlocks * 128 + 128);
    try std.testing.expectEqual(file.blocks.len, file.header.totalFileBlocks);

    const block = file.blocks[0];
    _ = block; // autofix
    // try std.testing.expectEqual(std.meta.activeTag(block), .Empty);
    // for (file.blocks) |b| {
    //     std.debug.print("{s}\n", .{@tagName(b.type)});
    // }
}
