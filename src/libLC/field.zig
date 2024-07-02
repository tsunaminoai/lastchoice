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
    pub fn fromInt(int: u8) ?TypeTag {
        switch (int) {
            1 => return .General,
            2 => return .Numeric,
            3 => return .Date,
            4 => return .Time,
            5 => return .Bool,
            else => return null,
        }
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

    pub fn fromSlice(comptime tag: TypeTag, allocator: std.mem.Allocator, text: []const u8) !Type.typeFromTag(tag) {
        return switch (tag) {
            .General => try Text.init(allocator, text),
            .Numeric => try std.fmt.parseFloat(f32, text),
            .Date => try Type.parseDate(text),
            .Time => try Type.parseTime(text),
            .Bool => if (text[0] == 'Y') true else false,
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

pub fn Field(comptime Tag: TypeTag) type {
    const f = struct {
        name: *Text,
        values: std.ArrayList(Type.typeFromTag(Tag)),
        type: TypeTag = Tag,

        const F = @This();

        var alloc: std.mem.Allocator = undefined;

        pub fn init(allocator: std.mem.Allocator, name: *Text) !F {
            alloc = allocator;
            return F{
                .name = name,
                .values = std.ArrayList(Type.typeFromTag(Tag)).init(alloc),
            };
        }
        pub fn initWithName(allocator: std.mem.Allocator, name: []const u8) !F {
            alloc = allocator;
            return F{
                .name = try Text.init(alloc, name),
                .values = std.ArrayList(Type.typeFromTag(Tag)).init(alloc),
            };
        }
        pub fn deinit(self: F) void {
            if (Tag == .General) {
                for (self.values.items) |value| {
                    if (value) |str| str.deinit();
                }
            }
            self.values.deinit();
            self.name.deinit();
        }
        pub fn addValue(self: *F, value: Type.typeFromTag(Tag)) !void {
            try self.values.append(value);
        }
        pub fn getValues(self: F) []Type.typeFromTag(Tag) {
            return self.values.items;
        }
    };

    return f;
}

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

    var f = try Field(.General).init(alloc, t);
    defer f.deinit();

    try std.testing.expect(std.mem.eql(u8, f.name.string.items, "First name"));
    try std.testing.expectEqual(@TypeOf(f.values.items), []?*Text);
    try f.addValue(try Type.fromSlice(.General, alloc, "Second name"));

    var n = try Field(.Numeric).initWithName(alloc, "Numeric field");
    defer n.deinit();

    try n.addValue(try Type.fromSlice(.Numeric, alloc, "10.5"));
    try std.testing.expectEqual(n.values.items[0], 10.5);

    var d = try Field(.Date).initWithName(alloc, "Date field");
    defer d.deinit();

    try d.addValue(try Type.fromSlice(.Date, alloc, "10/11/12"));
    try d.addValue(try Type.fromSlice(.Date, alloc, "10/11/89"));
    try std.testing.expectEqual(d.values.items[0], 20121011);
    try std.testing.expectEqual(d.values.items[1], 19891011);

    var b = try Field(.Bool).initWithName(alloc, "Bool field");
    defer b.deinit();
    try b.addValue(try Type.fromSlice(.Bool, alloc, "Y"));
    try b.addValue(try Type.fromSlice(.Bool, alloc, "N"));
    try std.testing.expectEqual(b.values.items[0], true);
    try std.testing.expectEqual(b.values.items[1], false);
}
