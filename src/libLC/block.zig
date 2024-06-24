const std = @import("std");

const Block_Size = 128;

const Block = @This();

type: Type,
data: [126]u8,

pub const Type = enum(u16) {
    Empty = 0x0,
    DataContinuation = 0x01,
    FormDescriptionContinuation = 0x02,
    TableViewContinuation = 0x03,
    FormulaContinuation = 0x04,
    DataRecord = 0x81,
    FormDescriptionView = 0x82,
    TableView = 0x83,
    Formula = 0x84,

    pub fn fromInt(int: u16) !Type {
        switch (int) {
            0x0...0x4, 0x81...0x84 => {
                return @as(Type, @enumFromInt(int));
            },
            else => {
                return error.InvalidBlockType;
            },
        }
    }

    pub fn fromSlice(int: []const u8) !Type {
        return @This().fromInt(std.mem.readInt(u16, int, .big));
    }
};

pub fn fromBytes(data: []u8) ![]align(1) Block {
    if (data.len % Block_Size != 0) {
        return error.InvalidBlockData;
    }

    return std.mem.bytesAsSlice(Block, data);
}

const cBlock = packed struct(128) {
    type: Type,
    data: [126]u8,
};
