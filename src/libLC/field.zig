const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;
const Text = @import("text.zig");

const Field = @This();

name: Text,
value: Value,

pub fn init(allocator: std.mem.Allocator, name: Text) !Field {
    if (name.field_type == null) {
        std.log.err("Field name must have a type", .{});
        return error.InvalidField;
    }
    return .{ .name = name, .value = switch (name.field_type.?) {
        .General => .{ .General = Text.init(allocator) },
        .Numeric => .{ .Numeric = 0.0 },
        .Date => .{ .Date = Text.init(allocator) },
        .Time => .{ .Time = 0.0 },
        .Bool => .{ .Bool = false },
    } };
}

pub fn deinit(self: Field) void {
    self.name.deinit();
    self.value.deinit();
}

pub const Kind = enum(u8) {
    General = 1,
    Numeric = 2,
    Date = 3,
    Time = 4,
    Bool = 5,
    pub fn fromInt(value: u8) ?Kind {
        if (value < 1 or value > 5) return null;
        return @enumFromInt(value);
    }
};

pub const Value = union(Kind) {
    General: ?Text,
    Numeric: f32,
    Date: Text,
    Time: f32,
    Bool: bool,

    pub fn deinit(self: Value) void {
        switch (self) {
            .General => |g| if (g) |txt| txt.deinit(),
            .Date => |d| d.deinit(),
            else => {},
        }
    }

    pub fn format(self: Value, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return switch (self) {
            .General => |g| if (g) |txt| try writer.print("{s}", .{txt.asSlice()}),
            .Numeric => |n| try writer.print("{d:0.2}", .{n}),
            .Date => |d| try writer.print("{s}", .{d.asSlice()}),
            .Time => |t| try writer.print("{d}", .{t}),
            .Bool => |b| if (b) try writer.writeAll("Y") else try writer.writeAll("N"),
        };
    }

    pub inline fn typeFromTag(tag: Kind) type {
        return switch (tag) {
            .General => ?Text,
            .Numeric => f32,
            .Date => Text,
            .Time => f32,
            .Bool => bool,
        };
    }

    pub fn fromSlice(tag: Kind, allocator: std.mem.Allocator, text: []const u8) !Value {
        return switch (tag) {
            .General => .{ .General = try Text.dupe(allocator, text) },
            .Numeric => .{ .Numeric = try std.fmt.parseFloat(f32, text) },
            .Date => .{ .General = try Text.dupe(allocator, text) },
            .Time => .{ .Time = try Value.parseTime(text) },
            .Bool => .{ .Bool = if (text[0] == 'Y') true else false },
        };
    }

    /// Parses a date in the format "MM/DD/YY"
    /// Returns a u32 in the format YYYYMMDD (ISO 8601 represent)
    pub fn parseDate(text: []const u8) !u32 {
        // if (text.len != 8 and text.len != 5) return error.InvalidDate;
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
