const std = @import("std");
const Text = @import("text.zig");

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

    pub fn fromSlice(tag: TypeTag, text: []const u8) !Type {
        return switch (tag) {
            .General => .{ .General = null },
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

pub fn Field(comptime Tag: TypeTag) type {
    const f = struct {
        name: *Text,
        values: std.ArrayList(Type),
        type: TypeTag = Tag,

        const F = @This();

        var alloc: std.mem.Allocator = undefined;

        pub fn init(allocator: std.mem.Allocator, name: *Text) !F {
            alloc = allocator;
            return F{
                .name = name,
                .values = std.ArrayList(Type).init(alloc),
            };
        }
        pub fn deinit(self: F) void {
            self.values.deinit();
            self.name.deinit();
        }
        pub fn addValue(self: *F, value: Type) !void {
            try self.values.append(value);
        }
        pub fn getValues(self: F) []Type {
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
    const t = try Text.initFromBytes(std.testing.allocator, &bytes);

    var f = try Field(.General).init(std.testing.allocator, t);
    defer f.deinit();

    try std.testing.expect(std.mem.eql(u8, f.name.string.items, "First name"));
    try std.testing.expectEqual(@TypeOf(f.values.items), []Type);
    try f.addValue(.{ .General = t });

    const t2 = try Text.init(std.testing.allocator, "Numeric field");
    var n = try Field(.Numeric).init(std.testing.allocator, t2);
    defer n.deinit();

    try n.addValue(try Type.fromSlice(.Numeric, "10.5"));
    try std.testing.expectEqual(n.values.items[0], Type{ .Numeric = 10.5 });

    const t3 = try Text.init(std.testing.allocator, "Date field");
    var d = try Field(.Numeric).init(std.testing.allocator, t3);
    defer d.deinit();

    try d.addValue(try Type.fromSlice(.Date, "10/11/12"));
    try d.addValue(try Type.fromSlice(.Date, "10/11/89"));
    try std.testing.expectEqual(d.values.items[0], Type{ .Date = 20121011 });
    try std.testing.expectEqual(d.values.items[1], Type{ .Date = 19891011 });

    std.debug.print("{}\n", .{d.values.items[0]});
}
