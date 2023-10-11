const std = @import("std");
const FCF = @import("fcf.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

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
    _,
};

pub const Block = extern struct {
    recordType: BlockTypeInt,
    data: *[126]u8,
};

pub const Empty = extern struct {
    entry1: u16 = 0,
    entry2: u16 = 0,
};

pub const BlockIndex = enum(u16) {
    None = 0xFFFF,
    _,
};

pub fn readBlocks(size: usize, buffer: []const u8, alloc: Allocator) !ArrayList(Block) {
    var blockList = ArrayList(Block).init(alloc);
    errdefer blockList.deinit();

    var window = std.mem.window(u8, buffer, size, @sizeOf(Block));
    while (window.next()) |*block| {
        const blockTag = std.mem.readIntSliceBig(u16, block.*);
        const newBlock = Block{
            .recordType = @as(BlockTypeInt, @enumFromInt(blockTag)),
            .data = undefined,
        };

        std.mem.copyForwards(u8, newBlock.data, buffer[2..]);
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
