const std = @import("std");
const Text = @import("text.zig");
const FCF = @import("fcf.zig");

const FieldType = enum(u8) {
    Text,
    Numeric,
    Date,
    Time,
    Bool,
    _,
    pub fn decode(byte: u8) FieldType {
        const check = byte & 0xF;
        std.log.debug("{X} -> {X}\n", .{ check, check });
        if (byte & 0x80 == 0x80) {
            return @as(FieldType, @enumFromInt(byte & 0xF));
        } else {
            return @as(FieldType, @enumFromInt(byte));
        }
    }
};

pub const Field = struct {
    fieldType: FieldType = FieldType.Text,
    fieldStyle: Text.TextStyles = Text.TextStyles{},
    name: std.ArrayList(Text.TextCharacter) = undefined,

    pub fn print(self: *@This()) void {
        std.log.debug("Field: ", .{});

        for (self.name.items) |char| {
            std.log.debug("{c}", .{char.char});
        }
        std.log.debug(" : {s} ({any})\n", .{ @tagName(self.fieldType), self.fieldStyle });
    }

    pub fn deinit(self: *@This()) void {
        self.name.deinit();
    }
};

pub fn decodeField(bytes: []const u8, size: usize, alloc: std.mem.Allocator) !Field {
    return Field{
        .fieldType = FieldType.decode(bytes[0]),
        .fieldStyle = @as(Text.TextStyles, @bitCast(bytes[1] & 0xF)),
        .name = try Text.decodeText(bytes[2..], size, alloc),
    };
}
