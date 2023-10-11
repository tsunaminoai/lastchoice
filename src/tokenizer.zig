const std = @import("std");

const data = "\x00\x0E\xCE\x90\xC1\x90\xCD\x90\xC5\x90\x81\x90\x0D\x0D\x00\x10\xC3\x90\xCC\x90\xC1\x90\xD3\x90\xD3\x90\x81\x90\x0D\x0D\x00\x16\xD6\x90\xCF\x90\xC3\x90\xC1\x90\xD4\x90\xC9\x90\xCF\x90\xCE\x90\x81\x90\x0D\x0D\x00\x13\xCD\x90\xCF\x90\xD6\x90\xC5\x90\xC4\x90\x80\x90\xD4\x90\xCF\x90\x81\x90\x0D\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00H\x00\x07";

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

const TextStyles = packed struct(u8) {
    normal: bool = false,
    underline: bool = false,
    bold: bool = false,
    italic: bool = false,
    _padding: enum(u4) { unset } = .unset,
};

const Baseline = packed struct(u8) {
    normalBackground: bool = false,
    sub: bool = false,
    subBackground: bool = false,
    super: bool = false,
    superBackground: bool = false,
    _padding: enum(u3) { unset } = .unset,
};

const TextCharacter = struct {
    char: u8 = 0,
    style: TextStyles = TextStyles{},
    baseline: Baseline = Baseline{},
};

const Field = struct {
    fieldType: FieldType = FieldType.Text,
    fieldStyle: TextStyles = TextStyles{},
    name: std.ArrayList(TextCharacter) = undefined,

    pub fn print(self: *@This()) void {
        for (self.name.items) |char| {
            std.debug.print("{c}", .{char.char});
        }
        std.debug.print(" : {s} ({any})\n", .{ @tagName(self.fieldType), self.fieldStyle });
    }
};

fn decodeField(bytes: []const u8, size: usize, alloc: std.mem.Allocator) !Field {
    return Field{
        .fieldType = FieldType.decode(bytes[0]),
        .fieldStyle = @as(TextStyles, @bitCast(bytes[1] & 0xF)),
        .name = try decodeText(bytes[2..], size, alloc),
    };
}

fn decodeText(bytes: []const u8, size: usize, alloc: std.mem.Allocator) !std.ArrayList(TextCharacter) {
    var idx: usize = 0;
    _ = size;

    var string = std.ArrayList(TextCharacter).init(alloc);
    errdefer string.deinit();

    while (idx < bytes.len - 1) {
        var newChar = TextCharacter{};

        if (bytes[idx] & 0x80 == 0x80) {
            if (bytes[idx] == 0x80) newChar.char = ' ' else newChar.char = bytes[idx] & 0x7F;

            if (bytes[idx + 1] & 0xD0 == 0xD0) {
                newChar.baseline = @as(Baseline, @bitCast(bytes[idx + 2] & 0xF));
                try string.append(newChar);
                idx += 3;
            } else {
                newChar.style = @as(TextStyles, @bitCast(bytes[idx + 1] & 0xF));
                try string.append(newChar);
                idx += 2;
            }
        } else {
            newChar.char = bytes[0];
            try string.append(newChar);
            idx += 1;
        }
    }

    // std.log.info("String: {any}", .{string});
    return string;
}

pub fn main() anyerror!void {
    std.log.debug("Data: {s}", .{std.fmt.bytesToHex(data, .upper)});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var alloc = gpa.allocator();

    var tok = std.mem.tokenizeAny(u8, data, "\x0d");
    while (tok.next()) |t| {
        const num = std.mem.readIntSliceBig(u16, t[0..2]);
        // const textBytes = t[2..];
        var strippedBytes = try alloc.alloc(u8, t.len - 2);
        defer alloc.free(strippedBytes);

        var f = try decodeField(t, num, alloc);
        defer f.name.deinit();
        f.print();
        // try decodeField(data, alloc);

        //     std.mem.copy(u8, strippedBytes, textBytes);
        //     for (strippedBytes) |*b| {
        //         b.* &= 0x7F;
        //     }
        //     switch (textBytes[0]) {
        //         0x0...0x80 => |c| {
        //             std.log.debug("Normal byte: {X}: '{c}'", .{ c, c });
        //         },
        //         0x81...0x8F => |c| {
        //             std.log.debug("Field Type byte: {X}: '{c}'", .{ c, c });
        //         },
        //         0x90...0x9F => |c| {
        //             std.log.debug("Field Style byte: {X}: '{c}'", .{ c, c });
        //         },
        //         0xC0...0xCF => |c| {
        //             std.log.debug("Normal byte needing stripped: {X}: '{c}'", .{ c, c & 0x7f });
        //         },
        //         0xD0...0xDF => |c| {
        //             std.log.debug("Background Style byte: {X}: '{c}'", .{ c, c & 0x7F });
        //         },
        //         else => |c| {
        //             std.log.debug("Unhandled byte: {X}: '{c}'", .{ c, c });
        //         },
        //     }
        //     std.log.debug("{}: {any}\nStripped: {any}\nString: {s}", .{ num, textBytes, strippedBytes, strippedBytes });
    }
}
