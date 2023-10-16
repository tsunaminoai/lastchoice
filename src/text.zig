const std = @import("std");
const FCF = @import("fcf.zig");

const expect = std.testing.expect;
/// TextStyles is a packed struct that represents the various styles that can be applied to a character.
pub const TextStyles = packed struct(u8) {
    normal: bool = false,
    underline: bool = false,
    bold: bool = false,
    italic: bool = false,
    _padding: enum(u4) { unset } = .unset,
};

// Baseline is a packed struct that represents the various baselines that can be applied to a character.
pub const Baseline = packed struct(u8) {
    normalBackground: bool = false,
    sub: bool = false,
    subBackground: bool = false,
    super: bool = false,
    superBackground: bool = false,
    _padding: enum(u3) { unset } = .unset,
};

/// TextCharacter is a struct that represents a single character in a text string.  It contains the character itself, as well as the styles and baselines that should be applied to it.
pub const TextCharacter = struct {
    char: u8 = 0,
    style: TextStyles = TextStyles{},
    baseline: Baseline = Baseline{},
    fieldType: FCF.FieldType = .Text,

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        return std.fmt.format(writer, "{c}", .{self.char});
    }
};

test "TextCharacter" {
    var char = TextCharacter{ .char = 'a' };
    var expected: u8 = 'a';
    var actual = char.char;

    try expect(expected == actual);
}

/// DecodeText takes a byte array and decodes it into a list of TextCharacters.
/// It does this by iterating over the bytes, and if the first bit is set, it
/// will read the next byte(s) as a style or baseline.
///
/// Callers are responsible for freeing the returned list.
// TODO: need to handle the control characters better.
// TODO: optionally strip strings
pub fn decodeText(bytes: []const u8, alloc: std.mem.Allocator) !std.ArrayList(TextCharacter) {
    var idx: usize = 0;

    var string = std.ArrayList(TextCharacter).init(alloc);
    errdefer string.deinit();

    while (idx < bytes.len) {
        var newChar = TextCharacter{};

        if (bytes[idx] & 0x80 == 0x80) {
            if (bytes[idx] == 0x80) newChar.char = ' ' else newChar.char = bytes[idx] & 0x7F;

            switch (bytes[idx + 1]) {
                0x90...0x9F => |x| { //field type
                    newChar.fieldType = try FCF.FieldType.fromInt(newChar.char);
                    newChar.style = @as(TextStyles, @bitCast(x));
                    try string.append(newChar);
                    idx += 2;
                },
                0x81...0x8F => |x| { // Regular text
                    newChar.style = @as(TextStyles, @bitCast(x));
                    try string.append(newChar);
                    idx += 2;
                },
                0xC0...0xDF => { // needs 3rd byte
                    newChar.baseline = @as(Baseline, @bitCast(bytes[idx + 2] & 0x0F));
                    try string.append(newChar);
                    idx += 3;
                },
                else => |x| {
                    std.debug.print("Unknown Text byte sequence:  0x{X:>02}\n", .{x});
                    try string.append(newChar);

                    idx += 1;
                },
            }
        } else {
            newChar.char = if (bytes[idx] == 0x0D or bytes[idx] == '\n') ' ' else bytes[idx];
            // TODO: Make this optional, but not let it affect field definitions
            //try string.append(newChar);
            idx += 1;
        }
    }

    return string;
}
test "Decode Field Text" {
    var gpa = std.testing.allocator;
    // "CLASS"
    var numericFieldBytes = &[_]u8{ 0xc3, 0x90, 0xcc, 0x90, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x81, 0x90, 0x0d, 0x0d };
    var numericField = try decodeText(numericFieldBytes, gpa);
    defer numericField.deinit();
    // std.debug.print("{any}\n", .{numericField});

    try std.testing.expectEqual(numericField.pop().fieldType, FCF.FieldType.Numeric);
    // try std.testing.expectEqual(numericField.items[0].fieldStyle, FCF.FieldStyle.Normal);
}
