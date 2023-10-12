const std = @import("std");
const FCF = @import("fcf.zig");

pub const TextStyles = packed struct(u8) {
    normal: bool = false,
    underline: bool = false,
    bold: bool = false,
    italic: bool = false,
    _padding: enum(u4) { unset } = .unset,
};

pub const Baseline = packed struct(u8) {
    normalBackground: bool = false,
    sub: bool = false,
    subBackground: bool = false,
    super: bool = false,
    superBackground: bool = false,
    _padding: enum(u3) { unset } = .unset,
};

pub const TextCharacter = struct {
    char: u8 = 0,
    style: TextStyles = TextStyles{},
    baseline: Baseline = Baseline{},
};

pub fn decodeText(bytes: []const u8, size: usize, alloc: std.mem.Allocator) !std.ArrayList(TextCharacter) {
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
