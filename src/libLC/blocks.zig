const std = @import("std");
const Schema = @import("schema.zig");

pub const Block_Size = 128;

pub const BlockList = []align(1) Block;
pub const Kind = enum(u16) {
    Empty = 0x0000,
    DataContinuation = 0x0001,
    FormDescriptionContinuation = 0x0002,
    TableViewContinuation = 0x0003,
    FormulaContinuation = 0x0004,
    DataRecord = 0x0081,
    FormDescriptionView = 0x0082,
    TableView = 0x0083,
    Formula = 0x0084,
    _,
};
pub const Block = extern struct {
    type: Kind,
    data: extern union {
        Schema: Form,
        DataRecord: DataRecord,
        common: Common,
    },

    const Common = extern struct {
        data: [126]u8,
    };
    const DataRecord = extern struct {
        num_blocks: u8,
        _: u8,
        data: [124]u8,
    };
    const Form = extern struct {
        num_blocks: u16,
        len_lines_on_screen: u16,
        len_lines: u16,
        data: [120]u8,
        pub fn format(self: Form, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("Schema Blocks: {}\n", .{self.num_blocks});
            try writer.print("Lines on Screen: {}\n", .{self.len_lines_on_screen});
            try writer.print("Lines: {}\n", .{self.len_lines});
        }

        pub fn fromBytes(bytes: []const u8) Form {
            return .{
                .num_blocks = std.mem.readInt(u16, bytes[0..2], .little),
                .len_lines_on_screen = std.mem.readInt(u16, bytes[2..4], .little),
                .len_lines = std.mem.readInt(u16, bytes[4..6], .little),
                .data = bytes[6..126],
            };
        }
        pub fn swapEndien(self: Form) Form {
            return .{
                .num_blocks = self.num_blocks,
                .len_lines_on_screen = @byteSwap(self.len_lines_on_screen),
                .len_lines = @byteSwap(self.len_lines),
                .data = self.data,
            };
        }
    };
};

pub fn fromBytes(data: []u8) !BlockList {
    if (data.len % Block_Size != 0) {
        return error.InvalidBlockData;
    }
    // std.debug.print("block: {}, data: {}\n", .{ @sizeOf(Block), data.len });
    return std.mem.bytesAsSlice(Block, data);
}

/// The magic string indicating a FirstChoice file
const MagicString = [14]u8{
    0x0C,
    0x47,
    0x45,
    0x52,
    0x42,
    0x49,
    0x4C,
    0x44,
    0x42,
    0x33,
    0x20,
    0x20,
    0x20,
    0x00,
};

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
    pub fn fromBytes(raw: *[128]u8) !Header {
        var head = std.mem.bytesToValue(Header, raw);
        if (!head.isValid())
            return error.InvalidMagicString;
        head.formDefinitionIndex -= 1; // removing the header block from count
        return head;
    }

    pub fn isValid(self: Header) bool {
        return std.mem.eql(u8, &self.magicString, &MagicString);
    }
    pub fn format(self: Header, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("Form Index: {}\n", .{self.formDefinitionIndex});
        try writer.print("Last Used Block: {}\n", .{self.lastUsedBlock});
        try writer.print("Total File Blocks: {}\n", .{self.totalFileBlocks});
        try writer.print("Data Records: {}\n", .{self.dataRecords});
        try writer.print("Available DB Fields: {}\n", .{self.availableDBFields});
        try writer.print("Form Length: {}\n", .{self.formLength});
        try writer.print("Form Revisions: {}\n", .{self.formRevisions});
        try writer.print("Empties Length: {}\n", .{self.emptiesLength});
        try writer.print("Table View Index: {}\n", .{self.tableViewIndex});
        try writer.print("Program Record Index: {}\n", .{self.programRecordIndex});
        try writer.print("Next Field Size: {}\n", .{self.nextFieldSize});
        try writer.print("Disk Var: {s}\n", .{self.diskVar});
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
    var head = try Header.fromBytes(&bytes);
    // std.debug.print("{s}\n", .{head});

    try std.testing.expectEqual(head.formDefinitionIndex, 8);
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
    std.debug.print("{any}\n", .{head});
}
