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
form: FCF.FormDefinition = undefined,

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

    self.blocks = @as([*]align(1) const FCF.Block, @ptrCast(self.data.ptr + BLOCK_SIZE))[0..self.header.totalFileBlocks];

    // get the form
    try stream.seekTo(self.header.formDefinitionIndex * BLOCK_SIZE);
    self.form = try reader.readStruct(FCF.FormDefinition);

    // get the fields
    const fieldDefs = self.data[(self.header.formDefinitionIndex * BLOCK_SIZE) + 8 .. (self.header.formDefinitionIndex * BLOCK_SIZE) + self.header.formLength];

    var tok = std.mem.tokenize(u8, fieldDefs, "\x0D");
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
        std.log.debug("{}, {s}", .{ fdef.size, fdef.name });
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
