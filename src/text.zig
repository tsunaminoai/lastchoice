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
    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        return std.fmt.format(writer, "N:{} U:{} B:{} I:{}", .{ self.normal, self.underline, self.bold, self.italic });
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

const ErrorList = std.ArrayList([]u8);

pub const Lexer = struct {
    src: []const u8,
    idx: usize = 0,
    isField: bool = false,

    pub fn init(src: []const u8, isfield: bool) Lexer {
        var lex = Lexer{
            .src = src,
            .idx = 0,
            .isField = isfield,
        };
        std.debug.print("Initializing Lexer as {any}\n", .{lex});
        return lex;
    }

    pub fn next(self: *Lexer) !?TextCharacter {
        std.debug.print("Lexer:next() idx: {} srcLen: {}\n", .{ self.idx, self.src.len });

        if (self.idx >= self.src.len) {
            return null;
        }
        var currentChar = self.currentUnchecked();
        var textCharacter = TextCharacter{ .char = currentChar };
        switch (currentChar) {
            // 0xD0 => {
            //     defer self.advance();
            //     textCharacter.char = ' ';
            //     return textCharacter;
            // },
            0x00...0x80 => |c| { // one byte ascii
                if (self.isField) {
                    defer self.advanceBy(2);
                } else {
                    defer self.advance();
                }

                switch (c) {
                    0x00 => return null,
                    0x1...0x20 => textCharacter.char = ' ',
                    0x80 => textCharacter.char = ' ',
                    else => {},
                }
                // std.log.debug("1 byte prog > {c}", .{currentChar});

                return textCharacter;
            },
            else => { // multibyte
                textCharacter.char = if (textCharacter.char != 0x0) textCharacter.char & 0x7F else ' ';

                const byte2 = self.peek() orelse return null;
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
                    0x0D => {
                        defer self.advanceBy(2);
                        textCharacter.char = ' ';
                        return textCharacter;
                    },
                    else => {
                        defer self.advanceBy(2);

                        std.log.debug("default prong> b1: {X:>02} b2: {X:>02}", .{ currentChar, byte2 });
                        return textCharacter;
                    },
                }
            },
        }
    }

    fn currentUnchecked(self: Lexer) u8 {
        return self.src[self.idx];
    }
    fn peek(self: Lexer) ?u8 {
        if (self.idx >= self.src.len - 1)
            return null;
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
    _ = gpa;
    // "CLASS"
    var textFieldBytes = &[_]u8{ 0xc3, 0x90, 0xcc, 0x90, 0xc1, 0x90, 0xd3, 0x90, 0xd3, 0x90, 0x83, 0x90, 0x0d, 0x0d };
    var lex = Lexer.init(textFieldBytes, true);
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
