const std = @import("std");
const Field = @This();

const TypeTag = enum(u8) {
    General = 1,
    Numeric = 2,
    Date = 3,
    Time = 4,
    Bool = 5,
    pub fn fromInt(int: u8) ?TypeTag {
        switch (int) {
            1 => return .General,
            2 => return .Numeric,
            3 => return .Date,
            4 => return .Time,
            5 => return .Bool,
            else => return null,
        }
    }
};

const Type = union(TypeTag) {
    General: []u8,
    Numeric: f32,
    Date: f32,
    Time: f32,
    Bool: bool,
};

type: TypeTag,
string: std.ArrayList(u8),
remaining: ?[]u8 = null,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, data: []u8) !Field {
    var self = Field{
        .allocator = allocator,
        .string = .{},
        .type = .General,
        .remaining = null,
    };

    const len = std.mem.readInt(u16, data[0..2], .big);
    const raw = data[2..];
    // std.debug.print("{X}\n", .{data[0..8]});
    if (len > 1000) {
        std.debug.print("Field length {} is too long ({x})\n", .{ len, data[0..2] });
        return error.FieldTooLong;
    }
    // std.debug.print("Field:\n\tlen: {d}\n", .{len});

    var length_count: usize = 0;
    var array_count: usize = 0;

    var string = std.ArrayList(u8){};
    errdefer string.deinit(allocator);
    var fieldType: TypeTag = .General;

    while (length_count < len) {
        // std.debug.print("Before: Len: {d}, array: {d}\n", .{ length_count, array_count });
        const char = raw[length_count];
        length_count += 1;
        array_count += 1;

        if (char < 0x80) {
            if (char == 0) {
                // std.debug.print("\tfound null\n", .{});
                break;
            } else if (char == 0x0d) {
                // std.debug.print("\tfound newline\n", .{});
                try string.append(allocator, ' ');
                length_count += 1;
            } else {
                // std.debug.print("\tfound ascii char: '{c}'\n", .{char});
                try string.append(allocator, char);
            }
        }
        // char >= 0x80
        else {
            const strippedChar = char & 0x7f;
            const d = raw[array_count];
            array_count += 1;
            length_count += 1;
            switch (d) {
                0xd0...0xdf => {
                    //  background text or field
                    const e = raw[array_count];
                    length_count += 1;
                    array_count += 1;
                    // std.debug.print("\tfound background: '{c}'\n", .{strippedChar});
                    if (e & 0x01 == 1) {
                        try string.append(allocator, strippedChar);
                    } else {
                        try string.append(allocator, strippedChar);
                    }
                },
                0x81...0x8f => {
                    // Normal text
                    // std.debug.print("\tfound normal Char: '{c}'\n", .{strippedChar});
                    try string.append(allocator, strippedChar);
                },
                0x90...0x9f => {
                    // Field Name / Type

                    if (TypeTag.fromInt(strippedChar)) |cap| {
                        // std.debug.print("\tfound type: {s}\n", .{@tagName(cap)});
                        fieldType = cap;
                    } else {
                        // std.debug.print("\tfound field Char: '{c}'\n", .{strippedChar});
                        try string.append(allocator, strippedChar);
                    }
                },
                0xC0...0xCF => {
                    // regular text
                    const e = raw[array_count];
                    _ = e; // autofix
                    array_count += 1;
                    length_count += 1;

                    // std.debug.print("\tfound regular Char: '{c}'\n", .{strippedChar});
                    try string.append(allocator, strippedChar);
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
    self.type = fieldType;
    // std.debug.print("\tString: \"{s}\"\n", .{string.items});
    // std.debug.print("\tType: \"{s}\"\n", .{@tagName(fieldType)});
    // std.debug.print("\tArray count: {}\"\n", .{array_count});
    // std.debug.print("\tLength count: {}\"\n", .{array_count});

    self.remaining = raw[array_count..];

    return self;
}

pub fn deinit(self: *Field) void {
    self.string.deinit(self.allocator);
}
