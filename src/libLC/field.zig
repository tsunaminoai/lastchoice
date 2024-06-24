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

    std.debug.print("{x}\n", .{data});

    var idx_of_non_space: usize = 0;
    while (data[idx_of_non_space] == 0x20) {
        idx_of_non_space += 1;
    }
    const len = std.mem.readInt(u16, @ptrCast(data[idx_of_non_space .. idx_of_non_space + 2]), .big);
    const raw = data[idx_of_non_space + 1 ..];

    std.debug.print("Field:\n\tlen: {d} (raw: 0x{x}\n", .{ len, data[idx_of_non_space .. idx_of_non_space + 2] });

    var length_count: usize = 0;
    var array_count: usize = 0;

    var string = std.ArrayList(u8).init(alloc);
    var fieldType: TypeTag = .General;

    while (length_count < len and idx_of_non_space + 2 + length_count < data.len) {
        const char = data[idx_of_non_space + 2 + length_count];
        length_count += 1;
        array_count += 1;

        switch (char) {
            0x00...0x79 => {
                switch (char) {
                    0x0d => {
                        try string.append('\n');
                        length_count += 1;
                    },
                    else => {
                        if (char == 0x00) {
                            try string.append(' ');
                        } else {
                            try string.append(char);
                        }
                    },
                }
            },
            else => {
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
                    0x90...0x9f => {
                        if (TypeTag.fromInt(strippedChar)) |cap| {
                            std.debug.print("found type: {s}\n", .{@tagName(cap)});
                            fieldType = cap;
                        } else {
                            try string.append(strippedChar);
                        }
                    },
                    0x81...0x8f => {
                        try string.append(strippedChar);
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
            },
        }
    }

    self.string = string;
    self.type = fieldType;
    std.debug.print("String: \"{s}\"\n", .{string.items});
    std.debug.print("Type: \"{s}\"\n", .{@tagName(fieldType)});
    if (array_count < data.len) {
        self.remaining = data[array_count..];
    }

    return self;
}

pub fn deinit(self: *Field) void {
    self.string.deinit();
    alloc.destroy(self);
}
