const std = @import("std");
const FCF = @import("fcf.zig");

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

pub const Block = extern struct { recordType: BlockTypeInt, data: [126]u8 };

pub const Empty = extern struct { entry1: u16, entry2: u16 };

pub const BlockIndex = enum(u16) {
    None = 0xFFFF,
    _,
};

pub fn parseBlocks(self: *FCF) !void {
    for (self.blocks.?.items) |b| {
        switch (b.recordType) {
            .FormDescriptionView => {
                self.form = try self.readForm(b);
            },
            else => {},
        }
    }
}

pub fn peekBlock(self: *FCF) FCF.Error!?BlockTypeInt {
    if (self.index + @sizeOf(Block) > self.buffer.?.len) return null;
    const tagInt = std.mem.readIntSlice(u16, self.buffer.?[self.index + 1 .. self.index + 3], std.builtin.Endian.Little);
    const tag = @as(BlockTypeInt, @enumFromInt(tagInt));

    return tag;
}
