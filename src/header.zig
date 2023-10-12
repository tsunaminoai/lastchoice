const std = @import("std");
const Block = @import("block.zig");
const FCF = @import("fcf.zig");

const MagicString = "GREIBDL3B    ";
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

    pub fn print(self: @This()) void {
        const fmt =
            \\
            \\Form Index: {}
            \\Last Block: {}
            \\Total Blocks: {}
            \\Data Records: {}
            \\Available Fields: {}
            \\Form Length: {}
            \\Form Revisions: {}
            \\Empties Length: {}
            \\Table Index: {}
            \\Program Index: {}
            \\Next Field Size: {}
            \\@DISKVAR: "{s}"
            \\
        ;
        std.log.debug(fmt, .{
            self.formDefinitionIndex,
            self.lastUsedBlock,
            self.totalFileBlocks,
            self.dataRecords,
            self.availableDBFields,
            self.formLength,
            self.formRevisions,
            self.emptiesLength,
            self.tableViewIndex,
            self.programRecordIndex,
            self.nextFieldSize,
            self.diskVar,
        });
    }

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
    // 0000000 0009 001c 001c 0008 470c 5245 4942 444c
    // 0000010 3342 2020 0020 000d 0126 0002 0000 0000
    // 0000020 ffff ffff 0000 0002 0008 0000 0000 0000
    // 0000030 0000 0000 0000 0000 0000 0000 0000 0000
    // zig fmt: off
    // zig fmt: on
    var bytes = [_]u8{
        0x00, 0x09, 0x00, 0x1c, 0x00, 0x1c, 0x00, 0x08,
        0x47, 0x0c, 0x52, 0x45, 0x49, 0x42, 0x44, 0x4c,
        0x33, 0x42, 0x20, 0x20, 0x00, 0x20, 0x00, 0x0d,
        0x01, 0x26, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00,
        0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x02,
        0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
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
    try std.testing.expectEqual(head.formDefinitionIndex, 9);
    try std.testing.expectEqual(head.lastUsedBlock, 28);
    try std.testing.expectEqual(head.totalFileBlocks, 28);
    try std.testing.expectEqual(head.dataRecords, 8);
    try std.testing.expect(std.mem.eql(u8, &head.magicString, MagicString));
    try std.testing.expectEqual(head.availableDBFields, 32);
    try std.testing.expectEqual(head.formLength, 13);
    try std.testing.expectEqual(head.formRevisions, 38);
    try std.testing.expectEqual(head.emptiesLength, 2);
    try std.testing.expectEqual(head.tableViewIndex, 0);
    try std.testing.expectEqual(head.programRecordIndex, 0);
    try std.testing.expectEqual(head.nextFieldSize, 8);
}
