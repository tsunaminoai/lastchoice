const std = @import("std");
const Text = @import("text.zig");

name: Text,
values: std.ArrayList(Type),

pub const TypeTag = enum(u8) {
    General = 1,
    Numeric = 2,
    Date = 3,
    Time = 4,
    Bool = 5,
    pub fn fromInt(value: u8) ?TypeTag {
        if (value < 1 or value > 5) return null;
        return @enumFromInt(value);
    }
};

pub const Type = union(TypeTag) {
    General: ?*Text,
    Numeric: f32,
    Date: u32,
    Time: f32,
    Bool: bool,

    pub inline fn typeFromTag(tag: TypeTag) type {
        return switch (tag) {
            .General => ?*Text,
            .Numeric => f32,
            .Date => u32,
            .Time => f32,
            .Bool => bool,
        };
    }

    pub fn fromSlice(comptime tag: TypeTag, allocator: std.mem.Allocator, text: []const u8) !Type {
        return switch (tag) {
            .General => .{ .General = try Text.init(allocator, text) },
            .Numeric => .{ .Numeric = try std.fmt.parseFloat(f32, text) },
            .Date => .{ .Date = try Type.parseDate(text) },
            .Time => .{ .Time = try Type.parseTime(text) },
            .Bool => .{ .Bool = if (text[0] == 'Y') true else false },
        };
    }

    /// Parses a date in the format "MM/DD/YY"
    /// Returns a u32 in the format YYYYMMDD (ISO 8601 represent)
    pub fn parseDate(text: []const u8) !u32 {
        if (text.len != 8) return error.InvalidDate;
        const month = try std.fmt.parseInt(u32, text[0..2], 10);
        const day = try std.fmt.parseInt(u32, text[3..5], 10);
        var year = try std.fmt.parseInt(u32, text[6..], 10);
        // Its 2024 and I'm fixing a Y2K bug
        if (year < 70) {
            year += 2000;
        } else {
            year += 1900;
        }

        return year * 10000 + month * 100 + day;
    }
    pub fn parseTime(text: []const u8) !f32 {
        _ = text; // autofix
        return 0.0;
    }
};

pub const Base = struct {
    name: *Text,
    values: std.ArrayList(Type),
    type: TypeTag,

    var alloc: std.mem.Allocator = undefined;

    pub fn init(allocator: std.mem.Allocator, name: *Text, tag: TypeTag) !*Base {
        alloc = allocator;
        const self = try allocator.create(Base);
        errdefer allocator.destroy(self);
        self.* = .{
            .name = name,
            .type = tag,
            .values = std.ArrayList(Type).init(alloc),
        };
        return self;
    }
    pub fn initWithName(allocator: std.mem.Allocator, name: []const u8, tag: TypeTag) !*Base {
        alloc = allocator;
        const self = try allocator.create(Base);
        errdefer allocator.destroy(self);
        self.* = .{
            .name = try Text.init(alloc, name),
            .type = tag,
            .values = std.ArrayList(Type).init(alloc),
        };
        return self;
    }

    pub fn deinit(self: *Base) void {
        if (self.type == .General) {
            for (self.values.items) |value| {
                if (value.General) |str| str.deinit();
            }
        }
        self.values.deinit();
        self.name.deinit();
        alloc.destroy(self);
    }
    pub fn addValue(self: *Base, value: Type) !void {
        try self.values.append(value);
    }
    pub fn getValues(self: Base) []Type {
        return self.values.items;
    }
};

test "Field" {
    var bytes: [0x32 + 2]u8 = [_]u8{
        0x00, 0x32, 0xc6, 0x90, 0xe9, 0x90, 0xf2, 0x90,
        0xf3, 0x90, 0xf4, 0x90, 0x80, 0x90, 0xee, 0x90,
        0xe1, 0x90, 0xed, 0x90, 0xe5, 0x90, 0x81, 0x90,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
    };
    const alloc = std.testing.allocator;
    const t = try Text.initFromBytes(alloc, &bytes);

    var f = try Base.init(alloc, t, .General);
    defer f.deinit();

    try std.testing.expect(std.mem.eql(u8, f.name.string.items, "First name"));
    try f.addValue(try Type.fromSlice(.General, alloc, "Second name"));

    var n = try Base.initWithName(alloc, "Numeric field", .Numeric);
    defer n.deinit();

    try n.addValue(try Type.fromSlice(.Numeric, alloc, "10.5"));
    try std.testing.expectEqual(n.values.items[0].Numeric, 10.5);

    var d = try Base.initWithName(alloc, "Date field", .Date);
    defer d.deinit();

    try d.addValue(try Type.fromSlice(.Date, alloc, "10/11/12"));
    try d.addValue(try Type.fromSlice(.Date, alloc, "10/11/89"));
    try std.testing.expectEqual(d.values.items[0].Date, 20121011);
    try std.testing.expectEqual(d.values.items[1].Date, 19891011);

    var b = try Base.initWithName(alloc, "Bool field", .Bool);
    defer b.deinit();
    try b.addValue(try Type.fromSlice(.Bool, alloc, "Y"));
    try b.addValue(try Type.fromSlice(.Bool, alloc, "N"));
    try std.testing.expectEqual(b.values.items[0].Bool, true);
    try std.testing.expectEqual(b.values.items[1].Bool, false);
}
