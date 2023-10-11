const std = @import("std");
const FCF = @import("fcf.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const Error = error{
    InvalidBlockType,
};

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

pub const BlockIndex = enum(u16) {
    None = 0xFFFF,
    _,
};

pub fn readBlocks(numBlocks: usize, buffer: []u8, alloc: Allocator) !ArrayList(Block) {
    var blockList = ArrayList(Block).init(alloc);
    errdefer blockList.deinit();

    var blocks = std.mem.window(u8, buffer, numBlocks, @sizeOf(Block));
    outer: while (blocks.next()) |*block| {
        std.log.debug("{any}\n", .{block});
        const blockTag = BlockTypeInt.fromSlice(block.ptr[0..2]) catch |err| {
            if (err == Error.InvalidBlockType) {
                std.log.warn("Unknown blocktype: 0x{s}", .{std.fmt.bytesToHex(block.ptr[0..2], .upper)});
                continue :outer;
            } else return err;
        };
        var newBlock = Block{
            .recordType = blockTag,
            .data = undefined,
        };
        var data = try alloc.alloc(u8, 126);
        std.mem.copy(u8, data, block.ptr[2..128]);
        newBlock.data = data;
        try blockList.append(newBlock);
    }

    return blockList;
}

pub fn parseBlocks(self: *FCF) !void {
    std.log.debug("<parseBlocks>", .{});
    for (self.blocks.?.items) |b| {
        switch (b.recordType) {
            .FormDescriptionView => {
                self.form = try self.readForm(b);
            },
            else => {},
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
