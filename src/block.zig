const std = @import("std");
const FCF = @import("fcf.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const BLOCK_SIZE = 128;

pub const Error = error{
    InvalidBlockType,
} || std.mem.Allocator.Error;

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
        return @This().fromInt(std.mem.readIntSliceBig(u16, int));
    }
};

pub const Block = struct {
    recordType: BlockTypeInt,
    data: []u8,

    pub fn deinit(self: *@This(), alloc: Allocator) void {
        alloc.free(self.data);
    }
};

pub const Empty = extern struct {
    entry1: u16 = 0,
    entry2: u16 = 0,
};

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
        var data = try alloc.alloc(u8, BLOCK_SIZE - 2);
        std.mem.copy(u8, data, block.ptr[2..BLOCK_SIZE]);

        newBlock.data = data;
        try blockList.append(newBlock);
        i += 1;
    }

    return blockList;
}

pub fn parseBlocks(blocks: std.ArrayList(Block)) !void {
    std.log.debug("<parseBlocks>", .{});
    for (blocks.items) |b| {
        switch (b.recordType) {
            .Empty => continue,
            else => {
                std.log.warn("Unknown block type: {s}", .{@tagName(b.recordType)});
            },
        }
    }
    std.log.debug("</parseBlocks>", .{});
}

pub fn peekBlock(self: *FCF) FCF.Error!?BlockTypeInt {
    std.log.debug("<peekBlock index={} buffer={}>", .{ self.index, self.buffer.?.len });
    if (self.index + @sizeOf(Block) > self.buffer.?.len) return null;
    const tagInt = std.mem.readIntSlice(u16, self.buffer.?[self.index + 1 .. self.index + 3], std.builtin.Endian.Little);
    const tag = @as(BlockTypeInt, @enumFromInt(tagInt));
    std.log.debug("</peekBlock>", .{});

    return tag;
}
