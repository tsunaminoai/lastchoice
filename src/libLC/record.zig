const std = @import("std");
const Field = @import("field.zig");
const Schema = @import("schema.zig");

const String = std.ArrayList(u8);

fields: *std.ArrayList(*Field),

pub fn Value(
    comptime T: Field.Type,
) type {
    return struct {
        rawValue: String,
        value: T,

        const Self = @This();

        pub fn init(raw: String) Self {
            return Self{
                .rawValue = raw,
                .value = switch (T) {
                    .General => Field.Type{ .General = raw.items },
                    // Field.Type.Numeric => std.mem.f32LoadBig(data.items),
                    // Field.Type.Date => std.mem.f32LoadBig(data.items),
                    // Field.Type.Time => std.mem.f32LoadBig(data.items),
                    // Field.Type.Bool => field.string.items[0] == 1,
                    else => undefined,
                },
            };
        }
    };
}

test "Record" {
    const allocator = std.testing.allocator;

    var string = std.ArrayList(u8).init(allocator);
    try string.appendSlice("Hello, World!!");

    const record = try Value(Field.Type.General).init(.General, string);
    try std.testing.expectEqual(record.value, "Hello, World!!");
}
