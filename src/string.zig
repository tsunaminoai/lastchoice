const std = @import("std");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
/// Text characters come in different flavors and need to be treated differently.
pub const CharacterTag = enum {
    space,
    field,
    background,
    data,
};

pub const Style = packed struct {
    underline: bool = false,
    bold: bool = false,
    italic: bool = false,

    pub fn fromInt(int: u8) Style {
        return @bitCast(@as(u3, @truncate(int)));
    }
    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        const bold = "\x1B[31;1m";
        const underline = "\x1B[31;4m";
        const italic = "\x1B[31;3m";
        if (self.bold) try std.fmt.format(writer, "{s}", .{bold});
        if (self.underline) try std.fmt.format(writer, "{s}", .{underline});
        if (self.italic) try std.fmt.format(writer, "{s}", .{italic});
    }
};

pub const BaseLine = enum {
    super,
    normal,
    sub,
    space,

    pub fn fromInt(int: u8, comptime tag: CharacterTag) BaseLine {
        _ = int;
        _ = tag;
        return .normal;
    }
};

const Character = struct {
    style: Style = Style{},
    char: u8,
    base: BaseLine = .normal,

    pub fn format(self: Character, fmt: []const u8, options: anytype, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (self.style.bold or self.style.underline or self.style.italic)
            try std.fmt.format(writer, "{s}", .{self.style});
        try std.fmt.format(writer, "{c}", .{self.char});

        const end = "\x1B[0m";
        if (self.style.bold or self.style.underline or self.style.italic)
            try std.fmt.format(writer, "{s}", .{end});
    }
};

pub fn String(comptime T: CharacterTag) type {
    return struct {
        tag: CharacterTag = T,
        len: usize = 0,
        chars: std.ArrayList(Character),
        alloc: std.mem.Allocator,

        pub fn fromBytes(alloc: std.mem.Allocator, bytes: []const u8, size: usize) !String(T) {
            var string = String(T){
                .tag = T,
                .chars = std.ArrayList(Character).init(alloc),
                .alloc = alloc,
            };

            var idx: usize = 0;

            while (idx < size) {
                const char = bytes[idx];
                var newChar = Character{ .char = char };

                switch (char) {
                    0x00 => {},
                    0x01...0x20 => newChar.char = ' ',
                    0x21...0x79 => {},
                    // 0x80 => newChar.char = ' ',
                    else => {
                        newChar.char &= 0x7F;
                        idx += 1;
                        switch (bytes[idx] & 0x7F) {
                            0x50...0x5F => |c| {
                                newChar.style = Style.fromInt(c);
                                idx += 1;
                                newChar.base = BaseLine.fromInt(bytes[idx], .data);
                            },
                            0x01...0x1F => |c| {
                                newChar.style = Style.fromInt(c);
                            },
                            0x40...0x4F => |c| {
                                newChar.style = Style.fromInt(c);
                                idx += 1;
                                newChar.base = BaseLine.fromInt(bytes[idx], .data);
                            },
                            else => |c| {
                                std.debug.print("Cant decipher char '{c}' 0x{x:0<2} 0x{x:0<2}\n", .{ c, c, bytes[idx] });
                            },
                        }
                    },
                }
                std.debug.print("Found '{}' at index {}\n", .{ newChar, idx });
                try string.chars.append(newChar);
                idx += 1;
            }

            string.trimRight();
            string.len = string.chars.items.len;

            std.debug.print("String: '{}'\n", .{string});
            return string;
        }

        pub fn deinit(self: *String(T)) void {
            self.chars.deinit();
        }

        pub fn trimRight(self: *String(T)) void {
            var char = self.chars.getLast();
            while (char.char == ' ') {
                _ = self.chars.pop();
                char = self.chars.getLast();
            }
        }

        pub fn format(self: String(T), fmt: []const u8, options: anytype, writer: anytype) !void {
            _ = fmt;
            _ = options;
            for (self.chars.items) |char|
                try writer.print("{}", .{char});
        }
    };
}

test "String" {
    const gpa = std.testing.allocator;
    const bytes = &[_]u8{ 0xc3, 0x91, 0xcc, 0x93, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x83, 0x90, 0x0d, 0x0d };
    var string = try String(.field).fromBytes(gpa, bytes);
    defer string.deinit();
    try expectEqual(string.len, 8);
    try expectEqual(string.chars.items[0].char, 'C');
    try expectEqual(string.chars.items[0].style.underline, true);
    try expectEqual(string.chars.items[1].char, 'L');
    try expectEqual(string.chars.items[1].style.underline, true);
    try expectEqual(string.chars.items[1].style.bold, true);
    try expectEqual(string.chars.items[2].char, 'A');
    try expectEqual(string.chars.items[2].style.bold, false);
    try expectEqual(string.chars.items[3].char, 'S');
    try expectEqual(string.chars.items[4].char, 'S');
    std.debug.print("{}\n", .{string});
    // try expectEqual(string.chars.items[5].char, ' ');
    // try expectEqual(string.chars.items[6].char, ' ');
}
