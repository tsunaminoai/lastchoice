const std = @import("std");
const Field = @import("field.zig");
const Schema = @import("schema.zig");
const Text = @import("text.zig");
const Blocks = @import("blocks.zig");

const Value = Field.Type;

fields: *std.ArrayList(*Field),
values: []Value,

const Records = @This();

var alloc: std.mem.Allocator = undefined;
var data: []u8 = undefined;

pub fn init(
    allocator: std.mem.Allocator,
    schema: *Schema,
    header: Blocks.Header,
    blocks: Blocks.BlockList,
) !void {
    alloc = allocator;

    const first_block_idx = header.formDefinitionIndex + schema.num_blocks - 1;
    const num_data_blocks = header.lastUsedBlock - first_block_idx;

    data = try alloc.alloc(u8, num_data_blocks * Blocks.Block_Size);
    errdefer alloc.free(data);

    @memset(data, 0);
    var idx: usize = 0;
    for (0..num_data_blocks) |i| {
        const dataBlock = blocks[first_block_idx + i].DataRecord;
        @memcpy(data[idx .. idx + dataBlock.data.len], &dataBlock.data);
        idx += dataBlock.data.len;
    }
    std.debug.print("Records: {X}\n", .{data});

    idx = 0;
    while (idx < data.len) {
        const txt = try Text.initFromBytes(alloc, data[idx..]);
        errdefer txt.deinit();
        std.debug.print("{any}\n", .{txt});
        idx += txt.len;
    }

    // std.debug.print("{d} lines in the form screen\n", .{lines_in_form_screen});
    // std.debug.print("{d} length of lines\n", .{lines_length});
    // std.debug.print("{}", .{header});
    // std.debug.print("Length of form data: {}, {}\n", .{ data.len, header.availableDBFields + header.formLength });
}

pub fn deinit(self: *Records) void {
    _ = self; // autofix
    // self.values.deinit();
}

pub fn Values(
    comptime Tag: Field.TypeTag,
) type {
    const ValueType = Field.Type.tagToType(Tag);
    return struct {
        rawValue: []u8,
        value: @TypeOf(ValueType),

        const Self = @This();

        pub fn init(txt: Text) !Self {
            const raw = txt.string.items;
            return Self{
                .rawValue = raw,
                .value = switch (Tag) {
                    .General => .{ .General = raw.items },
                    .Numeric => .{ .Numeric = try std.fmt.parseFloat(f32, raw) },
                    Field.Type.Date => .{ .Date = blk: {
                        var iso8601: u32 = 19000000;
                        iso8601 += 10000 * try std.fmt.parseInt(u32, raw[6..8], 10);
                        iso8601 += 100 * try std.fmt.parseInt(u32, raw[3..5], 10);
                        iso8601 += try std.fmt.parseInt(u32, raw[0..2], 10);
                        break :blk iso8601;
                    } },
                    // Field.Type.Time => std.mem.f32LoadBig(data.items),
                    // Field.Type.Bool => field.string.items[0] == 1,
                    else => undefined,
                },
            };
        }
    };
}

// test "Record" {
//     const allocator = std.testing.allocator;

//     var string = std.ArrayList(u8).init(allocator);
//     defer string.deinit();
//     try string.appendSlice("Hello, World!!");

//     const generic = try Value(Field.Type.General).init(string);
//     try std.testing.expect(std.mem.eql(u8, generic.value.General.?, "Hello, World!!"));

//     string.clearRetainingCapacity();
//     try string.appendSlice("1.2");
//     const number = try Value(Field.Type.Numeric).init(string);
//     try std.testing.expectApproxEqAbs(number.value.Numeric, 1.2, 0.001);

//     string.clearRetainingCapacity();
//     try string.appendSlice("10/11/88");
//     const date = try Value(Field.Type.Date).init(string);
//     try std.testing.expectEqual(date.value.Date, 19881110);
// }
