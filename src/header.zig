const std = @import("std");
const Block = @import("block.zig");
const FCF = @import("fcf.zig");

// https://www.fileformat.info/format/foxpro/dbf.htm
// TODO: docs

const MagicString = [14]u8{ 0x0C, 0x47, 0x45, 0x52, 0x42, 0x49, 0x4C, 0x44, 0x42, 0x33, 0x20, 0x20, 0x20, 0x00 };
pub const Header = extern struct {
    formDefinitionIndex: u16, // block# - 1
    lastUsedBlock: u16, // not accurate
    totalFileBlocks: u16, // dont count header
    dataRecords: u16,
    magicString: [14]u8,
    availableDBFields: u16,
    formLength: u16,
    formRevisions: u16, // 1 indexed
    _1: u16,
    emptiesLength: u16,
    tableViewIndex: u16,
    programRecordIndex: u16,
    _2: u16,
    _3: u16,
    nextFieldSize: u8,
    diskVar: [128 - 41]u8,

    pub fn fromBytes(raw: *[128]u8) Header {
        var head = std.mem.bytesToValue(Header, raw);
        return head;
    }
};

fn getSlice(file_content: []const u8, file_offset: usize, count: usize) []align(1) Header {
    const ptr = @intFromPtr(file_content.ptr) + file_offset;
    return @as([*]align(1) Header, @ptrFromInt(ptr))[0..count];
}
test "read header" {
    // 09 00 1c 00 1c 00 08 00  0c 47 45 52 42 49 4c 44
    // 42 33 20 20 20 00 0d 00  26 01 02 00 00 00 00 00
    // ff ff ff ff 00 00 02 00  08 00 00 00 00 00 00 00
    // 00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00

    var bytes = [_]u8{
        0x09, 0x00, 0x1c, 0x00, 0x1c, 0x00, 0x08, 0x00,
        0x0c, 0x47, 0x45, 0x52, 0x42, 0x49, 0x4c, 0x44,

        0x42, 0x33, 0x20, 0x20, 0x20, 0x00, 0x0d, 0x00,
        0x26, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,

        0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x02, 0x00,
        0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,

        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };
    var head = Header.fromBytes(&bytes);
    // std.debug.print("{s}\n", .{head});

    try std.testing.expectEqual(head.formDefinitionIndex, 9);
    try std.testing.expectEqual(head.lastUsedBlock, 28);
    try std.testing.expectEqual(head.totalFileBlocks, 28);
    try std.testing.expectEqual(head.dataRecords, 8);
    try std.testing.expect(std.mem.eql(u8, &head.magicString, &MagicString));
    try std.testing.expectEqual(head.availableDBFields, 13);
    try std.testing.expectEqual(head.formLength, 294);
    try std.testing.expectEqual(head.formRevisions, 2);
    try std.testing.expectEqual(head.emptiesLength, 0);
    try std.testing.expectEqual(head.tableViewIndex, 0xFFFF);
    try std.testing.expectEqual(head.programRecordIndex, 0xFFFF);
    try std.testing.expectEqual(head.nextFieldSize, 8);
}
