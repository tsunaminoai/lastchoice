const std = @import("std");
const Schema = @import("schema.zig");

const Block_Size = 128;

// const Block = @This();

pub const BlockList = []align(1) Block;

type: Type,
data: [126]u8,

pub const Type = enum(u16) {
    Empty = 0x0000,
    DataContinuation = 0x0001,
    FormDescriptionContinuation = 0x0002,
    TableViewContinuation = 0x0003,
    FormulaContinuation = 0x0004,
    DataRecord = 0x0081,
    FormDescriptionView = 0x0082,
    TableView = 0x0083,
    Formula = 0x0084,

    pub fn fromInt(int: u16) !Type {
        switch (int) {
            0x0...0x4, 0x81...0x84 => {
                return @as(Type, @enumFromInt(int));
            },
            else => {
                return error.InvalidBlockType;
            },
        }
    }

    pub fn fromSlice(int: []const u8) !Type {
        return Type.fromInt(std.mem.readInt(u16, int, .big));
    }
};

pub const Block = union(Type) {
    Empty: cBlock,
    DataContinuation: cBlock,
    FormDescriptionContinuation: cBlock,
    TableViewContinuation: cBlock,
    FormulaContinuation: cBlock,
    DataRecord: cBlock,
    FormDescriptionView: FDV,
    TableView: cBlock,
    Formula: cBlock,
};
const FDV = extern struct {
    type: Type,
    num_blocks: u16,
    lines_in_form_screen: u16,
    lines_length: u16,
    data: [120]u8,
};

test "union" {
    const bytes: [128]u8 = [_]u8{
        0x00, 0x82, 0x00, 0x04, 0xd0, 0x01, 0x0e, 0x00, 0x32, 0x00, 0x90, 0xc6, 0x90, 0xe9, 0x90, 0xf2,
        0x90, 0xf3, 0x90, 0xf4, 0x90, 0x80, 0x90, 0xee, 0x90, 0xe1, 0x90, 0xed, 0x90, 0xe5, 0x90, 0x81,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x18, 0x00, 0x90, 0xcc,
        0x90, 0xe1, 0x90, 0xf3, 0x90, 0xf4, 0x90, 0x80, 0x90, 0xee, 0x90, 0xe1, 0x90, 0xed, 0x90, 0xe5,
        0x90, 0x81, 0x0d, 0x0d, 0x14, 0x00, 0x90, 0xc1, 0x90, 0xe4, 0x90, 0xe4, 0x90, 0xf2, 0x90, 0xe5,
        0x90, 0xf3, 0x90, 0xf3, 0x90, 0x81, 0x0d, 0x0d, 0x2c, 0x00, 0x90, 0xc3, 0x90, 0xe9, 0x90, 0xf4,
        0x90, 0xf9, 0x90, 0x81, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    };
    try std.testing.expectEqual(bytes[1], 0x82);
    const block = Block{ .FormDescriptionView = @bitCast(bytes) };
    std.debug.print("{X}\n", .{block.FormDescriptionView.type});
    std.debug.print("{any}\n", .{block});
}

pub fn fromBytes(data: []u8) !BlockList {
    if (data.len % Block_Size != 0) {
        return error.InvalidBlockData;
    }

    return std.mem.bytesAsSlice(Block, data);
}

const cBlock = extern struct {
    type: Type,
    data: [126]u8,
};

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
        head.formDefinitionIndex -= 1;
        return head;
    }

    pub fn isValid(self: Header) bool {
        return std.mem.eql(u8, &self.magicString, &MagicString);
    }
    pub fn format(self: Header, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt; // autofix
        _ = options; // autofix
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
