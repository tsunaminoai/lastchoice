const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;
const Field = @import("field.zig");
const Text = @This();

string: std.ArrayList(u8),
field_type: ?Field.Kind = null,
len: usize = 0,
extra: ?[]const u8 = null,

pub fn init(allocator: Allocator) Text {
    return .{
        .string = Array(u8).init(allocator),
    };
}

/// Creates a new Text from a slice of bytes.
pub fn dupe(allocator: std.mem.Allocator, txt: []const u8) !Text {
    var str = Text.init(allocator);
    errdefer str.deinit();
    try str.string.appendSlice(txt);
    return str;
}

/// Initializes a Text from a byte array.
pub fn initFromBytes(allocator: std.mem.Allocator, data: []const u8) !Text {
    var self = Text.init(allocator);
    const len = std.mem.readInt(u16, data[0..2], .big);
    // std.debug.print("Consuming: {X}\n", .{data});
    if (len > data.len - 2) {
        std.log.err("\nText length {} exceeds data length {}\nData: {X}", .{ len, data.len, data });
        return error.InvalidLength;
    }
    const slice = data[2..];

    var length_count: usize = 0;
    var array_count: usize = 0;

    var string = std.ArrayList(u8).init(allocator);
    errdefer string.deinit();
    var fieldType: ?Field.Kind = null;

    //TODO: Add text formatting
    while (length_count < len) {
        // std.debug.print("Before: Len: {d}, array: {d}, slice: {}\n", .{
        //     length_count,
        //     array_count,
        //     slice.len,
        // });
        const char = slice[length_count];
        length_count += 1;
        array_count += 1;

        if (char < 0x80) {
            if (char == 0) {
                // std.debug.print("\tfound null\n", .{});
                break;
            } else if (char == 0x0d) {
                // std.debug.print("\tfound newline\n", .{});
                try string.append(' ');
                length_count += 1;
            } else {
                // std.debug.print("\tfound ascii char: '{c}'\n", .{char});
                try string.append(char);
            }
        }
        // char >= 0x80
        else {
            const strippedChar = char & 0x7f;
            const d = slice[array_count];
            array_count += 1;
            length_count += 1;
            switch (d) {
                0xd0...0xdf => {
                    //  background text or field
                    const e = slice[array_count];
                    length_count += 1;
                    array_count += 1;
                    // std.debug.print("\tfound background: '{c}'\n", .{strippedChar});
                    if (e & 0x01 == 1) {
                        try string.append(strippedChar);
                    } else {
                        try string.append(strippedChar);
                    }
                },
                0x81...0x8f => {
                    // Normal text
                    // std.debug.print("\tfound normal Char: '{c}'\n", .{strippedChar});
                    try string.append(strippedChar);
                },
                0x90...0x9f => {
                    // Field Name / Type

                    if (Field.Kind.fromInt(strippedChar)) |cap| {
                        // std.debug.print("\tfound type: {s}\n", .{@tagName(cap)});
                        fieldType = cap;
                    } else {
                        // std.debug.print("\tfound field Char: '{c}'\n", .{strippedChar});
                        try string.append(if (0 == strippedChar) ' ' else strippedChar);
                    }
                },
                0xC0...0xCF => {
                    // regular text
                    const e = slice[array_count];
                    _ = e; // autofix
                    array_count += 1;
                    length_count += 1;

                    // std.debug.print("\tfound regular Char: '{c}'\n", .{strippedChar});
                    try string.append(strippedChar);
                },
                else => {
                    std.debug.print("Unknown char: 0x{X}\n", .{d});
                    @panic("Unknown char");
                },
            }
        }
        // std.debug.print("After: Len: {d}, array: {d}\n", .{ length_count, array_count });
    }

    // trim string
    while (string.items.len > 0 and string.getLast() == ' ') {
        _ = string.pop();
    }
    while (string.items.len > 0 and string.items[0] == ' ') {
        _ = string.orderedRemove(0);
    }

    self = .{
        .string = string,
        .field_type = fieldType,
        .len = len,
        .extra = chomp(slice[len - 2 ..]),
    };

    return self;
}

fn chomp(in: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 2 < in.len and std.mem.indexOfAny(u8, in[i .. i + 2], &[_]u8{ 0xD, 0x20 }) != null and std.mem.indexOfScalar(u8, in[i .. i + 1], 0) == null) : (i += 2) {}
    if (std.mem.allEqual(u8, in[i..], 0)) return null;
    return in[i..];
}

pub fn deinit(self: Text) void {
    self.string.deinit();
}

pub fn asSlice(self: Text) []u8 {
    return self.string.items;
}

pub fn format(self: Text, fmt: []const u8, options: anytype, writer: std.io.AnyWriter) !void {
    _ = fmt;
    _ = options;
    try writer.print(
        \\
        \\Text
        \\  .string = ''{s}'',
        \\  .field_type = {?},
        \\  .len = {},
        \\
        \\
    , .{ self.string.items, self.field_type, self.len });
}

test "Text" {
    var bytes: [0x32 + 2]u8 = [_]u8{
        0x00, 0x32, 0xc6, 0x90, 0xe9, 0x90, 0xf2, 0x90,
        0xf3, 0x90, 0xf4, 0x90, 0x80, 0x90, 0xee, 0x90,
        0xe1, 0x90, 0xed, 0x90, 0xe5, 0x90, 0x81, 0x90,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
    };
    var t = try Text.initFromBytes(std.testing.allocator, &bytes);
    defer t.deinit();

    // std.debug.print("''{s}''\n", .{t.string.items});
    try std.testing.expect(std.mem.eql(u8, t.string.items, "First name"));
    try std.testing.expectEqual(t.field_type.?, .General);
}
