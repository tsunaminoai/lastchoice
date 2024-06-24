const std = @import("std");
pub const Header = @import("header.zig").Header;
pub const Block = @import("block.zig");
pub const Empty = @import("block.zig").Empty;
pub const Text = @import("text.zig");
pub const String = @import("string.zig");
pub const Field = @import("field.zig");
pub const Form = @import("form.zig");
pub const Record = @import("record.zig");

const Allocator = std.mem.Allocator;

const Endien = std.builtin.Endian;
const bigToNative = std.mem.bigToNative;
const nativeToBig = std.mem.nativeToBig;

arena: std.heap.ArenaAllocator,
data: []const u8,

header: FCF.Header = undefined,

empties: std.ArrayList(FCF.Empty) = undefined,
form: FCF.Form = undefined,
records: std.ArrayList(FCF.Record) = undefined,

index: usize = 0,
stream: std.io.FixedBufferStream([]const u8) = undefined,

const magicString = "\x0cGERBILDB3   \x00";
const extension = "FOL";

pub const FCF = @This(); //FirstChoice File

pub const Error = error{ InvalidMagic, EndOfStream, UnhandledBlockType, BadTextCharacter } || anyerror;

pub const BLOCK_SIZE = 128;

pub fn parse(self: *FCF) !void {
    self.stream = std.io.fixedBufferStream(self.data);

    const reader = self.stream.reader();

    self.header = try reader.readStruct(FCF.Header);

    if (!std.mem.eql(u8, self.header.magicString[0..14], magicString)) {
        std.log.warn("Found magic string: '{s}'", .{self.header.magicString});
        return error.InvalidMagic;
    }

    try self.parseForm();

    try self.parseRecords();
}

pub fn printForm(self: *FCF, writer: anytype) !void {
    try writer.print("Form Header:\n", .{});

    const form = self.form;
    try writer.print("  Lines: {}\n", .{form.lines});
    try writer.print("  Length: {}\n", .{form.length});

    try writer.print("=" ** 20 ++ " Fields " ++ "=" ** 20 ++ "\n", .{});

    for (form.fields.items) |field| {
        try writer.print("{}\t({})\t{s}\n", .{ field, field.definition.size, field.fType.toStr() });
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
    try writer.writeAll("=" ** 20 ++ " RECORDS " ++ "=" ** 20 ++ "\n");

    for (self.records.items) |record| {
        idx += 1;
        try writer.print("| ", .{});

        for (record.fields.items) |field| {
            try writer.print(" {s} |", .{field.name});
        }

        try writer.writeAll("\n");
    }
}

fn parseForm(self: *FCF) !void {
    const alloc = self.arena.allocator();
    // get the formdata
    try self.stream.seekTo(self.header.formDefinitionIndex * BLOCK_SIZE);
    var reader = self.stream.reader();

    const formDef = try reader.readStruct(Form.Definition);

    self.form = Form{
        .definition = formDef,
        .lines = std.mem.bigToNative(u16, formDef.lines),
        .length = std.mem.bigToNative(u16, formDef.length),
        .fields = std.ArrayList(*Field).init(alloc),
    };

    // this block aggregates all the form data into a sinigle chunk,
    // so we dont have to worry about block ids and all that
    var formData: []u8 = try alloc.alloc(u8, BLOCK_SIZE * self.form.definition.numBlocks);
    @memset(formData, 0);
    for (0..self.form.definition.numBlocks) |i| {
        if (i == 0) {
            std.log.debug("Copying form data block 0", .{});
            const d = try reader.readBytesNoEof(120);
            std.mem.copyForwards(u8, formData, &d);
        } else {
            std.log.debug("Copying form data block {} from {} to {}", .{ i, 120 + (i - 1) * 126, 120 + (i * 126) });

            try reader.skipBytes(2, .{});
            const d = try reader.readBytesNoEof(126);
            std.mem.copyForwards(u8, formData[120 + (i - 1) * 126 .. 120 + (i * 126)], &d);
        }
    }
    std.log.debug("formData = {any}\n", .{formData});
    // get the fields
    {
        // beginning of the data
        var idx: usize = 0;
        while (idx < formData.len) {
            // get the size of the field in bytes
            var size = formData[idx + 1];
            // move index to after the the size description
            idx += 2;
            // if zero size, break
            if (size < 2)
                break;
            // size takes into account the size description, so remove that
            size -= 2;

            // dont overrun the data
            if (size + idx > formData.len)
                break;

            std.log.debug(">> Size: {}", .{size});

            // get the bytes for this field
            const fieldBytes = formData[idx .. idx + size];

            std.log.debug(">> idx: {} data: {any}\n", .{ idx, fieldBytes });
            // move the index to the next field definitoni
            idx += size;

            // set up name and char array
            var name: []u8 = try alloc.alloc(u8, 1);
            var chars = std.ArrayList(Text.TextCharacter).init(alloc);

            // init the "lexer"
            var lex = Text.Lexer.init(fieldBytes, true);
            var fieldType: Field.Type = undefined;
            var fieldStyle: ?Text.TextStyles = null;

            var i: usize = 0;
            // lex the string found
            while (try lex.next()) |char| {
                std.log.debug("{} Found {c} {any} ", .{ i, char.char, char });
                try chars.append(char);
                // if its a field style, record it
                if (fieldStyle == null) {
                    fieldStyle = char.style;
                    std.log.debug("with style {any} ", .{char.style});
                }
                // if its a field type, record it
                if (char.fieldType) |ftype| {
                    std.log.debug("with type {s} ", .{@tagName(ftype)});

                    fieldType = ftype;
                    continue;
                }
                // realloc and add to the name
                name = try alloc.realloc(name, i + 2);
                name[i] = char.char;
                i += 1;
            }
            // if there were chars found
            if (i > 0) {
                // create the field and append it
                var field = try Field.init(alloc, name, size, fieldType, fieldStyle);
                //todo: get rid of the lexer and use this instead
                field.name = try String.String(.field).fromBytes(alloc, fieldBytes);
                try self.form.fields.append(field);
            }
        }
        // sanity check
        if (self.form.fields.items.len != self.header.availableDBFields) {
            std.log.err("Expected {} fields, found {}.\n", .{ self.header.availableDBFields, self.form.fields.items.len });
            std.log.err("{any}\n", .{self.form.fields});
            // todo: this is a bug in the parser, not the file
            // https://github.com/tsunaminoai/lastchoice/issues/14
            return error.NotAllFieldsParsed;
        }
    }
}

pub fn parseRecords(self: *FCF) !void {
    const alloc = self.arena.allocator();
    self.records = std.ArrayList(FCF.Record).init(alloc);
    {
        const dataStartPosition = BLOCK_SIZE * (self.header.formDefinitionIndex + self.form.definition.numBlocks);
        var dataWindow = std.mem.window(u8, self.data[dataStartPosition..], BLOCK_SIZE, BLOCK_SIZE);
        var id: u32 = 1;
        while (dataWindow.next()) |block| {
            // skip data continuation, we'll handle that below
            if (block[0] == '\x01') continue;
            const numBlocks = std.mem.readInt(u16, block[2..4], .little);
            const extendBy = if (numBlocks > 1) numBlocks else 0;
            const recordBytes = block.ptr[4 .. 128 - 4 + (extendBy * BLOCK_SIZE)];

            var record = Record{
                .id = id,
                .fields = std.ArrayList(Field.Definition).init(alloc),
            };

            var tok = std.mem.tokenize(u8, recordBytes, "\x0D\x0D");
            while (tok.next()) |recordField| {
                if (recordField.len < 2) break;
                var lex = Text.Lexer.init(recordField[2..], false);
                var chars = std.ArrayList(Text.TextCharacter).init(alloc);
                var name: []u8 = try alloc.alloc(u8, 1);

                var i: usize = 0;

                while (try lex.next()) |char| {
                    try chars.append(char);

                    name = try alloc.realloc(name, i + 2);
                    name[i] = char.char;
                    i += 1;
                }
                if (i == 0) break;
                var f = try Field.init(alloc, name.ptr[0..i], 0, null, null);
                errdefer f.deinit();
                const field = Field.Definition{
                    .size = 0,
                    .chars = chars,
                    .name = @constCast(std.mem.trim(u8, name.ptr[0..i], " ")),
                };
                try record.fields.append(field);
                if (record.fields.items.len == self.header.availableDBFields)
                    break;
            }
            try self.records.append(record);
            id += 1;
        }
    }
}

pub fn toCSV(self: *FCF, writer: anytype) !void {
    const alloc = self.arena.allocator();
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    var fieldCount: usize = 0;
    for (self.form.fields.items) |f| {
        try writer.print("\"{s} ({s})\", ", .{ f.definition.name, f.fType.toStr() });
        fieldCount += 1;
    }
    try writer.writeAll("\n");
    for (self.records.items) |r| {
        for (r.fields.items) |f| {
            try writer.print("\"{}\", ", .{f});
        }
        try writer.writeAll("\n");
    }
}

test {
    _ = std.testing.refAllDecls(@This());
}

test "json" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    const T = struct { a: i32, b: []const u8 };
    try std.json.stringify(T{ .a = 123, .b = "xy" }, .{}, out.writer());
    try std.testing.expectEqualSlices(u8, "{\"a\":123,\"b\":\"xy\"}", out.items);
}
