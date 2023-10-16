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
        try writer.print("{s}\t({})\t{s}\n", .{ field.definition.name, field.definition.size, field.fType.toStr() });
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
// TODO: docs

const Record = struct {
    fields: std.ArrayList(FieldDefinition),
};
// TODO: docs

const FieldDefinition = struct {
    size: u16,
    chars: std.ArrayList(FCF.Text.TextCharacter),
    name: []u8,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const trimmed = std.mem.trim(u8, self.name, &std.ascii.whitespace);
        try writer.print("{s}", .{trimmed});
    }
};

pub const FieldStyle = enum(u4) {
    Normal,
    Underline,
    Bold,
    Italic,

    pub fn fromInt(int: u8) !FieldStyle {
        return switch (int & 0x0F) {
            0 => .Normal,
            1 => .Underline,
            2 => .Bold,
            4 => .Italic,
            else => {
                std.debug.print("Invalid Field Style: {X:>02}\n", .{int});
                return error.InvalidFieldStyle;
            },
        };
    }
};

pub const FieldType = enum(u5) {
    Text = 1,
    Numeric = 2,
    Date = 3,
    Time = 4,
    Bool = 5,
    _,
    pub fn fromInt(int: u8) ?FieldType {
        return switch (int) {
            1 => .Text,
            2 => .Numeric,
            3 => .Date,
            4 => .Time,
            5 => .Bool,
            else => null,
        };
    }
    pub fn toStr(self: @This()) []const u8 {
        return switch (self) {
            .Text => "Text",
            .Numeric => "Number",
            .Date => "Date",
            .Time => "Time",
            .Bool => "Bool",
            else => "Unknown",
        };
    }
};

pub const Field = struct {
    definition: FieldDefinition = undefined,
    fType: FieldType = .Text,
    fStyle: Text.TextStyles = .{ .normal = true },

    const Self = @This();

    pub fn init(ftype: FieldType, style: Text.TextStyles) Self {
        return Self{
            .fType = ftype,
            .fStyle = style,
        };
    }
    pub fn setDefinition(self: *Self, def: FieldDefinition) void {
        self.definition = def;
    }
};

fn parseForm(self: *FCF) !void {
    // get the formdata
    try self.stream.seekTo(self.header.formDefinitionIndex * BLOCK_SIZE);
    var reader = self.stream.reader();

    var formDef = try reader.readStruct(FCF.FormDefinition);

    self.form = Form{
        .definition = formDef,
        .lines = std.mem.bigToNative(u16, formDef.lines),
        .length = std.mem.bigToNative(u16, formDef.length),
        .fields = std.ArrayList(Field).init(self.arena),
    };

    // get the fields
    const formStart = self.header.formDefinitionIndex * BLOCK_SIZE;
    const formEnd = formStart + (self.form.definition.numBlocks) * BLOCK_SIZE;
    const fieldDefs = self.data[formStart + 8 .. formEnd - 8];
    // std.debug.print("{s}\n", .{std.fmt.bytesToHex(fieldDefs[0..306], .upper)});
    {

        // TODO: This really needs to handle the nulls as part of the string, unforuntately
        var tok = std.mem.tokenize(u8, fieldDefs, "\x00");
        while (tok.next()) |f| {
            var size = f[0];

            if (size == 0)
                continue;
            var name: []u8 = try self.arena.alloc(u8, 1);
            var chars = std.ArrayList(Text.TextCharacter).init(self.arena);

            var lex = Text.Lexer.init(f[1..], true);
            var fieldType: FieldType = undefined;
            var fieldStyle: ?Text.TextStyles = null;
            var i: usize = 0;
            while (try lex.next()) |char| {
                try chars.append(char);

                if (fieldStyle == null) {
                    fieldStyle = char.style;
                }
                if (char.fieldType) |ftype| {
                    fieldType = ftype;
                    continue;
                }
                name = try self.arena.realloc(name, i + 2);
                name[i] = char.char;
                i += 1;
            }

            var field: Field = undefined;
            if (fieldStyle) |fs| {
                field = Field.init(fieldType, fs);
            } else {
                field = Field.init(fieldType, .{ .normal = true });
            }
            field.setDefinition(FieldDefinition{
                .size = size,
                .chars = chars,
                .name = name,
            });
            try self.form.fields.append(field);
            if (self.form.fields.items.len == self.header.availableDBFields)
                break;
        }
        if (self.form.fields.items.len != self.header.availableDBFields) {
            std.debug.print("Expected {} fields, found {}.\n", .{ self.header.availableDBFields, self.form.fields.items.len });
            std.debug.print("{any}\n", .{self.form.fields});
            return error.NotAllFieldsParsed;
        }
    }
}

pub fn parseRecords(self: *FCF) !void {
    self.records = std.ArrayList(FCF.Record).init(self.arena);
    {
        const dataStartPosition = BLOCK_SIZE * (self.header.formDefinitionIndex + self.form.definition.numBlocks);
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
                var lex = Text.Lexer.init(recordField, false);
                var chars = std.ArrayList(Text.TextCharacter).init(self.arena);
                var name: []u8 = try self.arena.alloc(u8, 1);

                var i: usize = 0;

                while (try lex.next()) |char| {
                    try chars.append(char);

                    name = try self.arena.realloc(name, i + 2);
                    name[i] = char.char;
                    i += 1;
                }

                var field = FieldDefinition{
                    .size = 0,
                    .chars = chars,
                    .name = name,
                };
                try record.fields.append(field);
                if (record.fields.items.len == self.header.availableDBFields)
                    break;
            }
            try self.records.append(record);
        }
    }
}

// TODO: docs

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
    definition: FormDefinition,
    lines: u16,
    length: u16,
    fields: std.ArrayList(Field),
};

test {
    _ = std.testing.refAllDecls(@This());
}
