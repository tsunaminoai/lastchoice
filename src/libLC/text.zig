const std = @import("std");
const Field = @import("field.zig");
const Text = @This();

var alloc: std.mem.Allocator = undefined;

string: std.ArrayList(u8),
field_type: ?Field.TypeTag = null,

remaining: ?[]u8 = null,

const TextData = struct {
    len: u16,
    data: []u8,

    pub fn fromBytes(data: []u8) TextData {
        const len = std.mem.readInt(u16, data[0..2], .big);
        std.debug.assert(len <= data.len - 2);
        return TextData{ .len = len, .data = data[2 .. 2 + len] };
    }
};

/// Initializes a Text directly
pub fn init(allocator: std.mem.Allocator, txt: []const u8) !*Text {
    alloc = allocator;
    const self = try allocator.create(Text);
    errdefer allocator.destroy(self);

    var str = std.ArrayList(u8).init(alloc);
    errdefer str.deinit();
    try str.appendSlice(txt);
    self.* = .{
        .string = str,
    };
    return self;
}

/// Initializes a Text from a byte array.
pub fn initFromBytes(allocator: std.mem.Allocator, data: []u8) !*Text {
    alloc = allocator;
    const self = try allocator.create(Text);
    errdefer allocator.destroy(self);

    const td = TextData.fromBytes(data);

    // std.debug.print("{X}\n", .{data[0..8]});

    // std.debug.print("Field:\n\tlen: {d}\n", .{len});

    var length_count: usize = 0;
    var array_count: usize = 0;

    var string = std.ArrayList(u8).init(alloc);
    errdefer string.deinit();
    var fieldType: ?Field.TypeTag = null;

    //TODO: Add text formatting
    while (length_count < td.len) {
        // std.debug.print("Before: Len: {d}, array: {d}\n", .{ length_count, array_count });
        const char = td.data[length_count];
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
            const d = td.data[array_count];
            array_count += 1;
            length_count += 1;
            switch (d) {
                0xd0...0xdf => {
                    //  background text or field
                    const e = td.data[array_count];
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

                    if (Field.TypeTag.fromInt(strippedChar)) |cap| {
                        // std.debug.print("\tfound type: {s}\n", .{@tagName(cap)});
                        fieldType = cap;
                    } else {
                        // std.debug.print("\tfound field Char: '{c}'\n", .{strippedChar});
                        try string.append(if (0 == strippedChar) ' ' else strippedChar);
                    }
                },
                0xC0...0xCF => {
                    // regular text
                    const e = td.data[array_count];
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
    while (string.getLast() == ' ') {
        _ = string.pop();
    }

    self.string = string;
    self.field_type = fieldType;
    // std.debug.print("\tString: \"{s}\"\n", .{string.items});
    // std.debug.print("\tType: \"{s}\"\n", .{@tagName(fieldType)});
    // std.debug.print("\tArray count: {}\"\n", .{array_count});
    // std.debug.print("\tLength count: {}\"\n", .{array_count});

    self.remaining = td.data[array_count..];

    return self;
}

pub fn deinit(self: *Text) void {
    self.string.deinit();
    alloc.destroy(self);
}

pub fn asSlice(self: *Text) []u8 {
    return self.string.items;
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
