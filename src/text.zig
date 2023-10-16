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

    pub fn fromInt(int: u8) TextStyles {
        return @as(TextStyles, @bitCast(int));
    }
};

// Baseline is a packed struct that represents the various baselines that can be applied to a character.
pub const Baseline = packed struct(u8) {
    normalBackground: bool = false,
    sub: bool = false,
    subBackground: bool = false,
    super: bool = false,
    superBackground: bool = false,
    _padding: enum(u3) { unset } = .unset,

    pub fn fromInt(int: u8) Baseline {
        return @as(Baseline, @bitCast(int));
    }
};

/// TextCharacter is a struct that represents a single character in a text string.  It contains the character itself, as well as the styles and baselines that should be applied to it.
pub const TextCharacter = struct {
    char: u8 = 0,
    style: TextStyles = TextStyles{},
    baseline: Baseline = Baseline{},
    fieldType: ?FCF.FieldType = null,

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

        if (bytes[idx] > 0x80) {
            if (bytes[idx] == 0x80) newChar.char = ' ' else newChar.char = bytes[idx] & 0x7F;
            if (idx == bytes.len - 1) {
                try string.append(newChar);
                break;
            }
            switch (bytes[idx + 1]) {
                0x90...0x9F => |x| { //field type
                    newChar.fieldType = FCF.FieldType.fromInt(newChar.char).?;
                    newChar.style = TextStyles.fromInt(x);
                    try string.append(newChar);
                    idx += 2;
                },
                0x81...0x8F => |x| { // Regular text
                    newChar.style = TextStyles.fromInt(x);
                    try string.append(newChar);
                    idx += 2;
                },
                0xC0...0xDF => |x| { // needs 3rd byte
                    newChar.baseline = Baseline.fromInt(x);
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
            // TODO: Make this optional, but not let it affect field definitions
            if (bytes[idx] == 0x0D or bytes[idx] == '\n' or bytes[idx] == '\x00') {
                idx += 1;
                continue;
            }
            newChar.char = bytes[idx];
            try string.append(newChar);
            idx += 1;
        }
    }

    return string;
}
// test "Decode Field Text" {
//     var gpa = std.testing.allocator;
//     // "CLASS"
//     var textFieldBytes = &[_]u8{ 0xc3, 0x90, 0xcc, 0x90, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x81, 0x90, 0x0d, 0x0d };
//     var lex = Lexer.init(textFieldBytes,gpa);

//     var textField = try decodeText(textFieldBytes, gpa);
//     defer textField.deinit();
//     try std.testing.expectEqual(textField.pop().fieldType, FCF.FieldType.Text);

//     var numericFieldBytes = &[_]u8{ 0xc3, 0x90, 0xcc, 0x90, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x82, 0x90, 0x0d, 0x0d };
//     var numericField = try decodeText(numericFieldBytes, gpa);
//     defer numericField.deinit();
//     try std.testing.expectEqual(numericField.pop().fieldType, FCF.FieldType.Numeric);

//     var dateFieldBytes = &[_]u8{ 0xc3, 0x90, 0xcc, 0x90, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x83, 0x90, 0x0d, 0x0d };
//     var dateField = try decodeText(dateFieldBytes, gpa);
//     defer dateField.deinit();
//     try std.testing.expectEqual(dateField.pop().fieldType, FCF.FieldType.Date);

//     var timeFieldBytes = &[_]u8{ 0xc3, 0x90, 0xcc, 0x90, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x84, 0x90, 0x0d, 0x0d };
//     var timeField = try decodeText(timeFieldBytes, gpa);
//     defer timeField.deinit();
//     try std.testing.expectEqual(timeField.pop().fieldType, FCF.FieldType.Time);

//     var boolFieldBytes = &[_]u8{ 0xc3, 0x90, 0xcc, 0x90, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x85, 0x90, 0x0d, 0x0d };
//     var boolField = try decodeText(boolFieldBytes, gpa);
//     defer boolField.deinit();
//     try std.testing.expectEqual(boolField.pop().fieldType, FCF.FieldType.Bool);
// }

const ErrorList = std.ArrayList([]u8);

pub const Lexer = struct {
    src: []const u8,
    idx: usize = 0,
    isField: bool = false,

    pub fn init(src: []const u8, isfield: bool) Lexer {
        return Lexer{
            .src = src,
            .idx = 0,
            .isField = isfield,
        };
    }

    pub fn deinit(self: Lexer) void {
        self.errors.deinit();
    }

    pub fn next(self: *Lexer) !?TextCharacter {
        // const src = self.src;
        if (self.idx >= self.src.len) {
            return null;
        }
        var currentChar = self.currentUnchecked();
        var textCharacter = TextCharacter{ .char = currentChar };

        switch (currentChar) {
            0x00...0x80 => |c| { // one byte ascii
                if (self.isField) {
                    defer self.advanceBy(2);
                } else {
                    defer self.advance();
                }

                switch (c) {
                    0x00...0x20 => textCharacter.char = ' ',
                    0x80 => textCharacter.char = ' ',
                    else => {},
                }
                // std.log.debug("1 byte prog > {c}", .{currentChar});

                return textCharacter;
            },
            else => { // multibyte
                textCharacter.char &= 0x7F;
                const byte2 = self.peek();
                switch (byte2) {
                    0xD0...0xDF => {
                        defer self.advanceBy(3);
                        const byte3 = self.peekN(2);
                        // std.log.debug("D0DF prong> b1: {X:>02} b2: {X:>02} b3: {X:>02}", .{ currentChar, byte2, byte3 });

                        textCharacter.style = TextStyles.fromInt(byte2);
                        textCharacter.baseline = Baseline.fromInt(byte3);

                        return textCharacter;
                    },
                    0x90...0x9F => {
                        defer self.advanceBy(2);
                        // std.log.debug("909f prong> b1: {X:>02} b2: {X:>02}", .{ currentChar, byte2 });

                        //field definition
                        if (FCF.FieldType.fromInt(textCharacter.char)) |t| {
                            textCharacter.fieldType = t;
                        }
                        textCharacter.style = TextStyles.fromInt(byte2);
                        return textCharacter;
                    },
                    0x81...0x8F => {
                        defer self.advanceBy(2);
                        // std.log.debug("818f prong> b1: {X:>02} b2: {X:>02}", .{ currentChar, byte2 });

                        textCharacter.style = TextStyles.fromInt(byte2);
                        return textCharacter;
                    },
                    0xC0...0xCF => {
                        defer self.advanceBy(3);
                        const byte3 = self.peekN(2);
                        // std.log.debug("C0CF prong> b1: {X:>02} b2: {X:>02} b3: {X:>02}", .{ currentChar, byte2, byte3 });

                        textCharacter.style = TextStyles.fromInt(byte2);
                        textCharacter.baseline = Baseline.fromInt(byte3);

                        return textCharacter;
                    },
                    else => return null,
                }
            },
        }
    }

    fn currentUnchecked(self: Lexer) u8 {
        return self.src[self.idx];
    }
    fn peek(self: Lexer) u8 {
        return self.src[self.idx + 1];
    }
    fn peekN(self: Lexer, count: usize) u8 {
        return self.src[self.idx + count];
    }
    fn advanceBy(self: *Lexer, count: usize) void {
        self.idx += count;
    }
    fn advance(self: *Lexer) void {
        self.advanceBy(1);
    }
};

test "Lexer Text" {
    var gpa = std.testing.allocator;
    // "CLASS"
    var textFieldBytes = &[_]u8{ 0xc3, 0x90, 0xcc, 0x90, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x83, 0x90, 0x0d, 0x0d };
    var lex = Lexer.init(textFieldBytes, gpa);
    var char = try lex.next();
    try std.testing.expectEqual(char.?.char, 'C');
    char = try lex.next();
    try std.testing.expectEqual(char.?.char, 'L');
    char = try lex.next();
    try std.testing.expectEqual(char.?.char, 'A');
    char = try lex.next();
    try std.testing.expectEqual(char.?.char, 'S');
    char = try lex.next();
    try std.testing.expectEqual(char.?.char, 'S');
    char = try lex.next();
    try std.testing.expectEqual(char.?.fieldType.?, .Date);
}
