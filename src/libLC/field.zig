const std = @import("std");
const Field = @This();

var alloc: std.mem.Allocator = undefined;

const TypeTag = enum(u8) {
    General = ' ',
    Numeric = 'N',
    Date = 'D',
    Time = 'T',
    Bool = 'Y',
    pub fn fromInt(int: u8) ?TypeTag {
        switch (int) {
            ' ' => return .General,
            'N' => return .Numeric,
            'D' => return .Date,
            'T' => return .Time,
            'Y' => return .Bool,
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

pub fn init(allocator: std.mem.Allocator, data: []u8) !*Field {
    alloc = allocator;
    const self = try allocator.create(Field);
    errdefer allocator.destroy(self);

    const len = std.mem.readInt(u16, data[0..2], .big);
    const raw = data[2..];
    if (len > 1000) {
        std.debug.print("Field length {} is too long ({x})\n", .{ len, data[0..2] });
        return error.FieldTooLong;
    }
    std.debug.print("Field:\n\tlen: {d}\n", .{len});

    var length_count: usize = 0;
    var array_count: usize = 0;

    var string = std.ArrayList(u8).init(alloc);
    errdefer string.deinit();
    var fieldType: TypeTag = .General;

    while (length_count < len and length_count < raw.len) {
        std.debug.print("Len: {d}, array: {d}\n", .{ length_count, array_count });
        const char = raw[length_count];
        length_count += 1;
        array_count += 1;

        if (char < 0x80) {
            if (char == 0x0d) {
                try string.append('\n');
            } else {
                if (char == 0x00) {
                    try string.append(' ');
                } else {
                    try string.append(char);
                }
            }
            length_count += 1;
            array_count += 1;
        } else {
            const strippedChar = char & 0x7f;
            const d = raw[array_count];
            array_count += 1;
            length_count += 1;
            switch (d) {
                0xd0...0xdf => {
                    const e = raw[array_count];
                    array_count += 1;
                    length_count += 1;
                    if (e & 0x01 == 1) {
                        try string.append(strippedChar);
                    } else {
                        try string.append(strippedChar);
                    }
                },
                0x81...0x8f => {
                    try string.append(strippedChar);
                },
                0x90...0x9f => {
                    if (TypeTag.fromInt(strippedChar)) |cap| {
                        std.debug.print("\tfound type: {s}\n", .{@tagName(cap)});
                        fieldType = cap;
                    } else {
                        try string.append(strippedChar);
                    }
                },
                0xc0...0xcf => {
                    const e = raw[array_count];
                    _ = e; // autofix
                    array_count += 1;
                    length_count += 1;

                    try string.append(strippedChar);
                },
                else => undefined,
            }
        }
    }

    self.string = string;
    self.type = fieldType;
    std.debug.print("\tString: \"{s}\"\n", .{string.items});
    std.debug.print("\tType: \"{s}\"\n", .{@tagName(fieldType)});
    if (array_count < raw.len) {
        std.debug.print("\tFinal length: {}\"\n", .{array_count});

        self.remaining = raw[array_count..];
    }

    return self;
}

pub fn deinit(self: *Field) void {
    self.string.deinit();
    alloc.destroy(self);
}
