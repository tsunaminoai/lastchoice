const std = @import("std");

const FOL = @This();

header: Header,
blocks: []Block,

pub fn init(buffer: []u8) FOL {
    return .{
        .header = Header.fromBytes(buffer[0..128]),
        .blocks = @alignCast(std.mem.bytesAsSlice(Block, buffer[128..])),
    };
}

const Header = extern struct {
    formDefinitionIndex: u16, // The index number of the form definition
    lastUsedBlock: u16, // the last block used in the file. It is known not to be accurate in FirstChoice files
    totalFileBlocks: u16, // number of blocks in the file, minus the header
    dataRecords: u16, // the number of data records held in the file
    magicString: *const [14]u8, // the magic string
    availableDBFields: u16, // the number of fields in the schema
    formLength: u16, // number of blocks the schema takes up
    formRevisions: u16, // number of schema revisions. 1 indexed
    _1: u16 = 0, // padding
    emptiesLength: u16, // number of empties blocks
    tableViewIndex: u16, // index of the table view, if any
    programRecordIndex: u16, // index of the program record, if any
    _2: u16 = 0, // padding
    _3: u16 = 0, // padding
    nextFieldSize: u8, // size of the next field
    diskVar: *const [128 - 41]u8, // @DISKVAR value for formulas

    pub fn fromBytes(bytes: []const u8) Header {
        return .{
            .formDefinitionIndex = std.mem.readInt(u16, bytes[0..2], .little),
            .lastUsedBlock = std.mem.readInt(u16, bytes[2..4], .little),
            .totalFileBlocks = std.mem.readInt(u16, bytes[4..6], .little),
            .dataRecords = std.mem.readInt(u16, bytes[6..8], .little),
            .magicString = bytes[8..22],
            .availableDBFields = std.mem.readInt(u16, bytes[22..24], .little),
            .formLength = std.mem.readInt(u16, bytes[24..26], .little),
            .formRevisions = std.mem.readInt(u16, bytes[26..28], .little),
            .emptiesLength = std.mem.readInt(u16, bytes[30..32], .little),
            .tableViewIndex = std.mem.readInt(u16, bytes[32..34], .little),
            .programRecordIndex = std.mem.readInt(u16, bytes[34..36], .little),
            .nextFieldSize = bytes[40],
            .diskVar = bytes[41..128],
        };
    }

    pub fn schemaPosition(self: Header) u16 {
        return self.formDefinitionIndex - 1;
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
        try writer.print("Disk Var: '{s}'\n", .{self.diskVar});
    }
};

const Block = extern struct {
    type: enum(u16) {
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
    },
    data: extern union {
        Schema: Schema,
        DataRecord: DataRecord,
        _: Common,
    },
    const Common = extern struct {
        data: [126]u8,
    };
    const DataRecord = extern struct {
        num_blocks: u8,
        _: u8,
        data: [124]u8,
    };
    const Schema = extern struct {
        num_blocks: u16,
        len_lines_on_screen: u16,
        len_lines: u16,
        data: [120]u8,
        pub fn format(self: Schema, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt; // autofix
            _ = options; // autofix
            try writer.print("Schema Blocks: {}\n", .{self.num_blocks});
            try writer.print("Lines on Screen: {}\n", .{self.len_lines_on_screen});
            try writer.print("Lines: {}\n", .{self.len_lines});
        }
    };
};

test {
    var buf: [4096]u8 = undefined;
    var f = try std.fs.cwd().openFile("test/TESTDB.FOL", .{});
    defer f.close();

    const n = try f.readAll(&buf);
    const file = FOL.init(buf[0..n]);
    std.debug.print("Header: {}\n", .{file.header});
    std.debug.print("FDV: {}\n", .{file.blocks[file.header.schemaPosition()].data.Schema});
}
