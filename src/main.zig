const std = @import("std");
const FCF = @import("firstzig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var alloc = gpa.allocator();

    var f = FCF.init(alloc);
    defer f.deinit();

    try f.open("ALUMNI.FOL");

    f.form.print();
    std.log.debug("End", .{});
    return;
}
