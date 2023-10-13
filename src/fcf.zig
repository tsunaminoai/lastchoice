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
    std.log.debug("{s}", .{self.header});

    if (!std.mem.eql(u8, self.header.magicString[0..14], magicString)) {
        std.log.warn("Found magic string: '{s}'", .{self.header.magicString});
        return error.InvalidMagic;
    }

    self.blocks = @as([*]align(1) const FCF.Block, @ptrCast(self.data.ptr + BLOCK_SIZE))[0..self.header.totalFileBlocks];

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
    std.log.debug("{any}", .{self.form});
}

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

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;
        try writer.print("Form Header:\n", .{});

        try writer.print("  Lines: {}\n", .{self.lines});
        try writer.print("  Length: {}\n", .{self.length});

        try writer.print("=" ** 20 ++ "Fields" ++ "=" ** 20 ++ "\n", .{});

        for (self.fields.items) |field| {
            try writer.print("{s}\t({})\n", .{ field.name, field.size });
        }
    }
};
