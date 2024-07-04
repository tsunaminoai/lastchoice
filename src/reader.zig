const std = @import("std");

/// this is a side tangent, but I'm curious about just doing a Reader...
pub const Header = struct {
    const SIZE = 128;
    const Magic = "\x0CGERBILDb3   \x00";

    formDefinitionIndex: u16, // The index number of the form definition
    lastUsedBlock: u16, // the last block used in the file. It is known not to be accurate in FirstChoice files
    totalFileBlocks: u16, // number of blocks in the file, minus the header
    dataRecords: u16, // the number of data records held in the file
    magicString: *const [14]u8, // the magic string
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
        head.formDefinitionIndex -= 1; // removing the header block
        // head.formDefinitionIndex -= 1; // Accouting for 1 indexing
        return head;
    }

    pub fn findHeader(seekable_stream: anytype) !Header {
        var buf: [Header.SIZE]u8 = undefined;
        const read_buf: []u8 = buf[0..];
        try seekable_stream.seekTo(0);
        const read_len = try seekable_stream.context.reader().readAll(read_buf);
        if (read_len != Header.SIZE) {
            return error.InvalidHeaderSize;
        }
        const header: *align(1) Header = @ptrCast(&buf);

        // header.formDefinitionIndex = @byteSwap(header.formDefinitionIndex);
        return header.*;
    }

    pub fn isValid(self: Header) bool {
        _ = self; // autofix
        return true;
        // return std.mem.eql(u8, self.magicString, Header.Magic);
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

pub const SchemaRecord = struct {
    tag: u16 = 0x82,
    num_blocks: u16,
    lines_in_form_screen: u16,
    lines_length: u16,
    data: [120]u8,
};
pub fn readSchemaRecord(seekable_stream: anytype, stream_len: u64, header: Header) !SchemaRecord {
    var buf: [@sizeOf(SchemaRecord) + std.math.maxInt(u16)]u8 = undefined;
    const schema_len_max = @min(stream_len, buf.len);
    _ = schema_len_max; // autofix

    std.debug.print("pos: {}\n", .{try seekable_stream.getPos()});
    try seekable_stream.seekTo(header.formDefinitionIndex * Header.SIZE);
    var loaded_len: usize = 0;
    const read_buf: []u8 = buf[loaded_len..];

    loaded_len += try seekable_stream.context.reader().readAll(read_buf);
    std.debug.print("len: {} read_buf: {s}\n", .{ loaded_len, read_buf });
    return error.InvalidSchemaRecord;
}
test {
    const allocator = std.testing.allocator;
    _ = allocator; // autofix
    var f = try std.fs.cwd().openFile("test/TESTDB.FOL", .{});
    defer f.close();
    const s = f.seekableStream();
    const h = try Header.findHeader(s);
    try std.testing.expect(h.isValid());
    std.debug.print("{}\n", .{h});
    const schema = try readSchemaRecord(s, try f.getEndPos(), h);

    _ = schema; // autofix
}
pub fn Iterator(comptime SeekableStream: type) type {
    return struct {
        stream: SeekableStream,

        header: Header,
        record_start_offset: u64 = 0,
        schema_offset: u64 = 0,

        const Self = @This();

        pub fn init(stream: SeekableStream) !Self {
            const stream_len = try stream.getEndPos();
            _ = stream_len; // autofix
        }
    };
}
