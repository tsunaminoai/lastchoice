const std = @import("std");
const Block = @import("block.zig");
const FCF = @import("fcf.zig");

/// The magic string indicating a FirstChoice file
const MagicString = [14]u8{ 0x0C, 0x47, 0x45, 0x52, 0x42, 0x49, 0x4C, 0x44, 0x42, 0x33, 0x20, 0x20, 0x20, 0x00 };

/// The header is the first block in a FirstChoice file. It contains all the
/// necessary fields to reconstruct the data.
/// for more info see https://www.fileformat.info/format/foxpro/dbf.htm
pub const Header = extern struct {
    formDefinitionIndex: u16, // The index number of the form definition
    lastUsedBlock: u16, // the last block used in the file. It is known not to be accurate in FirstChoice files
    totalFileBlocks: u16, // number of blocks in the file, minus the header
    dataRecords: u16, // the number of data records held in the file
    magicString: [14]u8, // the magic string
    availableDBFields: u16, // the number of fields in the schema
    formLength: u16, // number of blocks the schema takes up
    formRevisions: u16, // number of schema revisions. 1 indexed
    _1: u16, // padding
    emptiesLength: u16, // number of empties blocks
    tableViewIndex: u16, // index of the table view, if any
    programRecordIndex: u16, // index of the program record, if any
    _2: u16, // padding
    _3: u16, // padding
    nextFieldSize: u8, // size of the next field
    diskVar: [128 - 41]u8, // @DISKVAR value for formulas

    /// Converts a 128 block into a Header for field access
    pub fn fromBytes(raw: *[128]u8) Header {
        return std.mem.bytesToValue(Header, raw);
    }
};

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
