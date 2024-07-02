// const std = @import("std");
// const Field = @import("field.zig");
// const Schema = @import("schema.zig");

// const String = std.ArrayList(u8);

// fields: *std.ArrayList(*Field),
// values: *std.ArrayList(Value(Field.TypeTag)),

// const Record = @This();
// var alloc: std.mem.Allocator = undefined;

// pub fn init(allocator: std.mem.Allocator, schema: Schema) !*Record {
//     alloc = allocator;
//     var self = try allocator.create(Record);
//     errdefer self.deinit();

//     self.* = Record{
//         .fields = schema.fields,
//         .values = try std.ArrayList(Value(Field.TypeTag)).init(allocator),
//     };
//     return self;
// }

// pub fn deinit(self: *Record) void {
//     self.values.deinit();
// }

// pub fn Value(
//     comptime Tag: Field.TypeTag,
// ) type {
//     const ValueType = Field.Type.tagToType(Tag);
//     return struct {
//         rawValue: []u8,
//         value: @TypeOf(ValueType),

//         const Self = @This();

//         pub fn init(raw: String) !Self {
//             return Self{
//                 .rawValue = raw.items,
//                 .value = switch (Tag) {
//                     .General => .{ .General = raw.items },
//                     .Numeric => .{ .Numeric = try std.fmt.parseFloat(f32, raw.items) },
//                     Field.Type.Date => .{ .Date = blk: {
//                         var iso8601: u32 = 19000000;
//                         iso8601 += 10000 * try std.fmt.parseInt(u32, raw.items[6..8], 10);
//                         iso8601 += 100 * try std.fmt.parseInt(u32, raw.items[3..5], 10);
//                         iso8601 += try std.fmt.parseInt(u32, raw.items[0..2], 10);
//                         break :blk iso8601;
//                     } },
//                     // Field.Type.Time => std.mem.f32LoadBig(data.items),
//                     // Field.Type.Bool => field.string.items[0] == 1,
//                     else => undefined,
//                 },
//             };
//         }
//     };
// }

// // test "Record" {
// //     const allocator = std.testing.allocator;

// //     var string = std.ArrayList(u8).init(allocator);
// //     defer string.deinit();
// //     try string.appendSlice("Hello, World!!");

// //     const generic = try Value(Field.Type.General).init(string);
// //     try std.testing.expect(std.mem.eql(u8, generic.value.General.?, "Hello, World!!"));

// //     string.clearRetainingCapacity();
// //     try string.appendSlice("1.2");
// //     const number = try Value(Field.Type.Numeric).init(string);
// //     try std.testing.expectApproxEqAbs(number.value.Numeric, 1.2, 0.001);

// //     string.clearRetainingCapacity();
// //     try string.appendSlice("10/11/88");
// //     const date = try Value(Field.Type.Date).init(string);
// //     try std.testing.expectEqual(date.value.Date, 19881110);
// // }
