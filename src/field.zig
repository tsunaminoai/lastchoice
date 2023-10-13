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
    fieldSize: u16 = 0,
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
        return std.fmt.format(writer, "\"{s}\" ({s}): {any}\n", .{ buffer, @tagName(self.fieldType), self.fieldStyle });
    }
};

pub fn decodeFields(bytes: []const u8, alloc: std.mem.Allocator) !std.ArrayList(Field) {
    var fType: FieldType = FieldType.Text;
    var fieldList = std.ArrayList(Field).init(alloc);
    errdefer fieldList.deinit();

    var tok = std.mem.tokenizeAny(u8, bytes, "\x0D\x0D");

    while (tok.next()) |fieldBytes| {
        var text = try Text.decodeText(fieldBytes[2..], alloc);
        errdefer text.deinit();

        var field = Field{
            .fieldType = fType,
            .fieldStyle = @as(Text.TextStyles, @bitCast(fieldBytes[2] & 0xF)),
            .fieldSize = std.mem.readIntSliceBig(u16, fieldBytes[0..2]),
            .name = text,
        };
        try fieldList.append(field);
    }

    return fieldList;
}

test "Field" {
    var alloc = std.testing.allocator;

    // this is for the whole form
    // const bytes = [_]u8{ 0x82, 0x00, 0x04, 0x00, 0x01, 0xD0, 0x00, 0x0E, 0x00, 0x32, 0xC6, 0x90, 0xE9, 0x90, 0xF2, 0x90, 0xF3, 0x90, 0xF4, 0x90, 0x80, 0x90, 0xEE, 0x90, 0xE1, 0x90, 0xED, 0x90, 0xE5, 0x90, 0x81, 0x90, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x18, 0xCC, 0x90, 0xE1, 0x90, 0xF3, 0x90, 0xF4, 0x90, 0x80, 0x90, 0xEE, 0x90, 0xE1, 0x90, 0xED, 0x90, 0xE5, 0x90, 0x81, 0x90, 0x0D, 0x0D, 0x00, 0x14, 0xC1, 0x90, 0xE4, 0x90, 0xE4, 0x90, 0xF2, 0x90, 0xE5, 0x90, 0xF3, 0x90, 0xF3, 0x90, 0x81, 0x90, 0x0D, 0x0D, 0x00, 0x2C, 0xC3, 0x90, 0xE9, 0x90, 0xF4, 0x90, 0xF9, 0x90, 0x81, 0x90, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 };

    const fieldBytes = [_]u8{
        0x00, 0x32, 0xC6, 0x90,
        0xE9, 0x90, 0xF2, 0x90,
        0xF3, 0x90, 0xF4, 0x90,
        0x80, 0x90, 0xEE, 0x90,
        0xE1, 0x90, 0xED, 0x90,
        0xE5, 0x90, 0x81, 0x90,
        0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
    };
    var fields = try decodeFields(&fieldBytes, alloc);
    defer {
        for (fields.items) |*field| {
            field.deinit();
        }
        fields.deinit();
    }

    var field = fields.items[0];

    std.debug.print("\n{any}\n", .{field});

    try std.testing.expect(field.fieldType == FieldType.Text);
    try std.testing.expect(field.fieldStyle.bold == true);
    std.debug.print("Length: {d}\n", .{field.name.items.len});
    try std.testing.expect(field.name.items.len == 38);
    try std.testing.expect(field.name.items[0].char == 'F');
    try std.testing.expect(field.name.items[1].char == 'i');
    try std.testing.expect(field.name.items[2].char == 'r');
    try std.testing.expect(field.name.items[3].char == 's');
    try std.testing.expect(field.name.items[4].char == 't');
}
