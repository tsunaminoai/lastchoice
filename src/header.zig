const std = @import("std");
const Block = @import("block.zig");

pub const Header = extern struct {
    formDefinitionIndex: u16, // block# - 1
    lastUsedBlock: u16, // not accurate
    totalFileBlocks: u16, // dont count header
    dataRecords: u16,
    magicString: [14]u8 align(1),
    availableDBFields: u16,
    formLength: u16,
    formRevisions: u16, // 1 indexed
    _1: u16,
    emptiesLength: u16,
    tableViewIndex: Block.BlockIndex,
    programRecordIndex: Block.BlockIndex,
    _2: u16,
    _3: u16,
    nextFieldSize: u8,
    diskVar: [128 - 41]u8,
};
