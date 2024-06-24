const std = @import("std");
const String = @import("string.zig");
const Field = @import("field.zig");

/// This is the schema for the records contained within the file
pub const Definition = extern struct {
    blockType: u16, // The block type tag
    // todo: remove this and use the block type

    numBlocks: u16, // Number of blocks the schema occupies
    lines: u16, // Number of lines taken in the form screen (Big Endian)
    length: u16, // Length plus lines plus 1
};

const Form = @This();

definition: Definition,
lines: u16,
length: u16,
fields: std.ArrayList(*Field),
