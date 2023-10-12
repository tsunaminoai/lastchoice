const std = @import("std");
const Text = @import("text.zig");
const FCF = @import("fcf.zig");

const Error = error{InvalidFieldType};

const FieldType = enum(u8) {
    Text = 1,
    Numeric,
    Date,
    Time,
    Bool,

    pub fn decode(byte: u8) Error!FieldType {
        // std.debug.print("Decode Field Type 0x{X} '{b}' -> {X}\n", .{ byte, byte, byte << 1 >> 1 });
        switch (byte) {
            0x81...0x85 => return @as(FieldType, @enumFromInt(byte << 1 >> 1)),
            else => return Error.InvalidFieldType,
        }
    }
};
test "Field type" {
    try std.testing.expect(try FieldType.decode(0x81) == FieldType.Text);
    try std.testing.expect(try FieldType.decode(0x82) == FieldType.Numeric);
    try std.testing.expect(try FieldType.decode(0x83) == FieldType.Date);
    try std.testing.expect(try FieldType.decode(0x84) == FieldType.Time);
    try std.testing.expect(try FieldType.decode(0x85) == FieldType.Bool);
}

pub const Field = struct {
    fieldType: FieldType = FieldType.Text,
    fieldStyle: Text.TextStyles = Text.TextStyles{},
    name: std.ArrayList(Text.TextCharacter) = undefined,

    pub fn print(self: *@This()) void {
        std.log.debug("Field: ", .{});

        for (self.name.items) |char| {
            std.log.debug("{c}", .{char.char});
        }
        std.log.debug(" : {any} ({any})\n", .{ self, self.fieldStyle });
    }

    pub fn deinit(self: *@This()) void {
        self.name.deinit();
    }

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        var buffer = std.mem.zeroes([128]u8);
        for (self.name.items, 0..) |c, i| {
            buffer[i] = c.char;
        }
        return std.fmt.format(writer, "{s} ({s}): {any}\n", .{ buffer, @tagName(self.fieldType), self.fieldStyle });
    }
};

pub fn decodeField(bytes: []const u8, alloc: std.mem.Allocator) !Field {
    var fType: FieldType = FieldType.Text;
    if (FieldType.decode(bytes[0])) |f| {
        fType = f;
    } else |err| {
        if (err == Error.InvalidFieldType) {
            std.log.warn("Invalid Field Type Byte: {X}", .{bytes[0]});
            return err;
        }
    }
    return Field{
        .fieldType = fType,
        .fieldStyle = @as(Text.TextStyles, @bitCast(bytes[1] & 0xF)),
        .name = try Text.decodeText(bytes[2..], alloc),
    };
}
