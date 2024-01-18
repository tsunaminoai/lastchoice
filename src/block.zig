const std = @import("std");
const FCF = @import("fcf.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const BLOCK_SIZE = 128;

pub const Error = error{
    InvalidBlockType,
} || std.mem.Allocator.Error;

/// Each 128 byte block has a type indicated by the first two bytes in BE
pub const BlockTypeInt = enum(u16) {
    Empty = 0x0,
    DataContinuation = 0x01,
    FormDescriptionContinuation = 0x02,
    TableViewContinuation = 0x03,
    FormulaContinuation = 0x04,
    DataRecord = 0x81,
    FormDescriptionView = 0x82,
    TableView = 0x83,
    Formula = 0x84,

    pub fn fromInt(int: u16) Error!BlockTypeInt {
        switch (int) {
            0x0...0x4, 0x81...0x84 => {
                return @as(BlockTypeInt, @enumFromInt(int));
            },
            else => {
                return Error.InvalidBlockType;
            },
        }
    }

    pub fn fromSlice(int: []const u8) Error!BlockTypeInt {
        return @This().fromInt(std.mem.readInt(u16, int, .big));
    }
};

/// FC Blocks are 128 bytes in size with the first 2 bytes indicating the block's type.
/// If the data the block contains extends beyond 128 bytes, it will be split into multiple
/// blocks using continuation type blocks following the initial data block.
pub const Block = extern struct {
    blockType: BlockTypeInt,
    data: [126]u8,
};

/// An "empty" is a pair of numbers. A list of these is stored in the 5th block
/// (FC Block #4) and can go on for several blocks. The number of these pairs
/// is contained in the header. It is known that some extra repeated pairs can persist.
pub const Empty = extern struct {
    entry1: u16 = 0,
    entry2: u16 = 0,
};

/// Takes a buffer of characters and returns an array of FC blocks.
pub fn readBlocks(buffer: []u8, alloc: Allocator) !ArrayList(Block) {
    var blockList = ArrayList(Block).init(alloc);
    errdefer blockList.deinit();

    var blocks = std.mem.window(u8, buffer[BLOCK_SIZE..], BLOCK_SIZE, BLOCK_SIZE);
    var i: usize = 0;
    outer: while (blocks.next()) |*block| {
        std.log.debug(
            "Reading block {}/{}",
            .{ i + 1, (buffer.len - BLOCK_SIZE) / BLOCK_SIZE },
        );
        const blockTag = BlockTypeInt.fromInt(block.ptr[0]) catch |err| {
            if (err == Error.InvalidBlockType) {
                std.log.debug("Skipping block {}", .{i});
                if (i != 0) std.log.warn(
                    "Unknown blocktype: 0x{s}",
                    .{std.fmt.bytesToHex(
                        block.ptr[0..2],
                        .upper,
                    )},
                );
                i += 1;

                continue :outer;
            } else return err;
        };
        var newBlock = Block{
            .recordType = blockTag,
            .data = undefined,
        };
        const data = try alloc.alloc(u8, BLOCK_SIZE - 2);

        std.mem.copy(u8, data, block.ptr[2..BLOCK_SIZE]);

        newBlock.data = data;
        try blockList.append(newBlock);
        i += 1;
    }

    return blockList;
}
