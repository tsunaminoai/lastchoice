const std = @import("std");
const FCF = @import("firstzig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var alloc = gpa.allocator();

    var f = FCF.init(alloc);
    defer f.deinit();

    try f.open("RESERVE.FOL");
}
