const std = @import("std");
const Header = @import("header.zig").Header;
const Block = @import("block.zig");
const Empty = @import("block.zig").Empty;
const Text = @import("text.zig");

const Allocator = std.mem.Allocator;

const Endien = std.builtin.Endian;
const bigToNative = std.mem.bigToNative;
const nativeToBig = std.mem.nativeToBig;

arena: Allocator,
data: []const u8,

header: FCF.Header = undefined,
blocks: []align(1) const FCF.Block = &[0]FCF.Block{},
empties: std.ArrayList(FCF.Empty) = undefined,
form: FCF.Form = undefined,
records: std.ArrayList(FCF.Record) = undefined,

index: usize = 0,

const magicString = "\x0cGERBILDB3   \x00";
const extension = "FOL";

pub const FCF = @This(); //FirstChoice File

pub const Error = error{ InvalidMagic, EndOfStream, UnhandledBlockType, BadTextCharacter } || anyerror;

pub const BLOCK_SIZE = 128;

pub fn parse(self: *FCF) !void {
    var stream = std.io.fixedBufferStream(self.data);

    const reader = stream.reader();

    self.header = try reader.readStruct(FCF.Header);

    if (!std.mem.eql(u8, self.header.magicString[0..14], magicString)) {
        std.log.warn("Found magic string: '{s}'", .{self.header.magicString});
        return error.InvalidMagic;
    }

    // get the formdata
    try stream.seekTo(self.header.formDefinitionIndex * BLOCK_SIZE);
    var formDef = try reader.readStruct(FCF.FormDefinition);

    self.form = Form{
        .lines = std.mem.bigToNative(u16, formDef.lines),
        .length = std.mem.bigToNative(u16, formDef.length),
        .fields = std.ArrayList(FieldDefinition).init(self.arena),
    };

    // get the fields
    const fieldDefs = self.data[(self.header.formDefinitionIndex * BLOCK_SIZE) + 8 .. (self.header.formDefinitionIndex * BLOCK_SIZE) + (2 * self.header.formLength)];
    {
        var tok = std.mem.tokenize(u8, fieldDefs, "\x0D\x0D");
        while (tok.next()) |f| {
            var chars = try FCF.Text.decodeText(f[2..], self.arena);
            var name: []u8 = try self.arena.alloc(u8, chars.items.len);
            for (0..name.len) |i| {
                name[i] = chars.items[i].char;
            }
            var fdef = FieldDefinition{
                .size = std.mem.readIntSliceBig(u16, f[0..2]),
                .chars = chars,
                .name = name,
            };
            try self.form.fields.append(fdef);
            if (self.form.fields.items.len >= self.header.availableDBFields) break;
        }
    }

    self.records = std.ArrayList(FCF.Record).init(self.arena);
    {
        const dataStartPosition = BLOCK_SIZE * (self.header.formDefinitionIndex + formDef.numBlocks);
        var dataWindow = std.mem.window(u8, self.data[dataStartPosition..], BLOCK_SIZE, BLOCK_SIZE);

        while (dataWindow.next()) |block| {
            // skip data continuation, we'll handle that below
            if (block[0] == '\x01') continue;
            var numBlocks = std.mem.readIntLittle(u16, block[2..4]);
            var extendBy = if (numBlocks > 1) numBlocks else 0;
            const recordBytes = block.ptr[4 .. 128 - 4 + (extendBy * BLOCK_SIZE)];

            var record = Record{
                .fields = std.ArrayList(FCF.FieldDefinition).init(self.arena),
            };

            var tok = std.mem.tokenize(u8, recordBytes, "\x0D\x0D");
            while (tok.next()) |recordField| {
                var chars = try FCF.Text.decodeText(recordField, self.arena);
                if (chars.items.len == 0 or recordField.len == 0) {
                    chars.deinit();
                    continue;
                }

                var name: []u8 = try self.arena.alloc(u8, chars.items.len);
                for (0..name.len) |i| {
                    name[i] = chars.items[i].char;
                }
                var field = FieldDefinition{
                    .size = 0,
                    .chars = chars,
                    .name = name,
                };
                try record.fields.append(field);
            }
            try self.records.append(record);
        }
    }
}

pub fn printForm(self: *FCF, writer: anytype) !void {
    try writer.print("Form Header:\n", .{});

    const form = self.form;
    try writer.print("  Lines: {}\n", .{form.lines});
    try writer.print("  Length: {}\n", .{form.length});

    try writer.print("=" ** 20 ++ "Fields" ++ "=" ** 20 ++ "\n", .{});

    for (form.fields.items) |field| {
        try writer.print("{s}\t({})\n", .{ field.name, field.size });
    }
}
pub fn printHeader(self: *FCF, writer: anytype) !void {
    const string =
        \\FirstChoice Database Header
        \\  Form Index: {}
        \\  Last Block: {}
        \\  Total Blocks: {}
        \\  Data Records: {}
        \\  Magic String: {s}
        \\  Available Fields: {}
        \\  Form Length: {}
        \\  Form Revisions: {}
        \\  Empties Length: {}
        \\  Table Index: {}
        \\  Program Index: {}
        \\  Next Field Size: {}
        \\  @DISKVAR: "{s}"
        \\
    ;
    const header = self.header;

    try writer.print(string, .{
        header.formDefinitionIndex,
        header.lastUsedBlock,
        header.totalFileBlocks,
        header.dataRecords,
        header.magicString,
        header.availableDBFields,
        header.formLength,
        header.formRevisions,
        header.emptiesLength,
        header.tableViewIndex,
        header.programRecordIndex,
        header.nextFieldSize,
        header.diskVar,
    });
}

pub fn printRecords(self: *FCF, writer: anytype) !void {
    var idx: u16 = 0;
    for (self.records.items) |record| {
        idx += 1;
        try writer.print("| ", .{});

        for (record.fields.items) |field|
            try writer.print(" {s} |", .{field.name});

        try writer.writeAll("\n");
    }
}

const Record = struct {
    fields: std.ArrayList(FieldDefinition),
};

const FieldDefinition = struct {
    size: u16,
    chars: std.ArrayList(FCF.Text.TextCharacter),
    name: []u8,
};

const FormDefinition = extern struct {
    /// The block type tag
    blockType: u16,

    /// Number of blocks the form definintion occupies
    numBlocks: u16,

    /// Number of lines taken in the form screen (Big Endian)
    lines: u16,

    /// Length plus lines plus 1
    length: u16,
};

const Form = struct {
    lines: u16,
    length: u16,
    fields: std.ArrayList(FieldDefinition),
};
