const std = @import("std");
const Text = @import("text.zig");
const String = @import("string.zig");

const Field = @This();

definition: *Definition = undefined,
name: String.String(.field) = undefined,
fType: Type = .Text,
fStyle: Text.TextStyles = .{},

var alloc: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator, name: []u8, size: u16, ftype: ?Type, style: ?Text.TextStyles) !*Field {
    alloc = allocator;
    const self = try alloc.create(Field);

    self.* = .{
        .definition = try Definition.init(alloc, size, name),
        .fType = ftype orelse .Text,
        .fStyle = style orelse .{},
    };
    return self;
}
pub fn deinit(self: *Field) void {
    self.definition.deinit(alloc);
}
pub fn format(
    self: Field,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    // try self.definition.format("{}", options, writer);
    try writer.print("{}", .{self.name});
}

/// A field definition is the actual data for a field
pub const Definition = struct {
    size: u16,
    chars: std.ArrayList(Text.TextCharacter),
    name: []u8,

    pub fn init(allocator: std.mem.Allocator, size: u16, field_name: []u8) !*Definition {
        const self = try allocator.create(Definition);
        errdefer allocator.destroy(self);
        self.* = .{
            .size = size,
            .chars = std.ArrayList(Text.TextCharacter).init(alloc),
            .name = field_name,
        };
        return self;
    }
    pub fn deinit(self: *Definition, allocator: std.mem.Allocator) void {
        self.chars.deinit();
        allocator.destroy(self);
    }

    pub fn format(
        self: Definition,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        // const trimmed = std.mem.trim(u8, self.name, &std.ascii.whitespace);
        // try writer.print("{s}", .{trimmed});

        for (self.chars.items) |c| {
            try writer.print("{}", .{c});
        }
    }
};

pub const Style = enum(u4) {
    Normal,
    Underline,
    Bold,
    Italic,

    pub fn fromInt(int: u8) !Style {
        return switch (int & 0x0F) {
            0 => .Normal,
            1 => .Underline,
            2 => .Bold,
            4 => .Italic,
            else => {
                std.debug.print("Invalid Field Style: {X:>02}\n", .{int});
                return error.InvalidFieldStyle;
            },
        };
    }
};

pub const Type = enum(u5) {
    Text = 1,
    Numeric = 2,
    Date = 3,
    Time = 4,
    Bool = 5,
    _,
    pub fn fromInt(int: u8) ?Type {
        return switch (int) {
            1 => .Text,
            2 => .Numeric,
            3 => .Date,
            4 => .Time,
            5 => .Bool,
            else => null,
        };
    }
    pub fn toStr(self: Type) []const u8 {
        return switch (self) {
            .Text => "Text",
            .Numeric => "Number",
            .Date => "Date",
            .Time => "Time",
            .Bool => "Bool",
            else => "Unknown",
        };
    }
};
