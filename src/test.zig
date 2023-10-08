const std = @import("std");
const Header = @import("main.zig").Header;
const Block = @import("main.zig").Block;
const BlockTag = @import("main.zig").BlockTypeInt;

const FormDescriptionBlock = extern struct {
    blockType: u16,
    totalBlocks: u16,
    lines: u16,
    length: u16,
    formData: [120]u8,
};

const Form = struct {
    lines: u16,
    length: u16,
    data: []u8,

    pub fn init(line: u16, len: u16, allocator: std.mem.Allocator) !Form {
        var data = try allocator.alloc(u8, len);

        return Form{
            .lines = line,
            .length = len,
            .data = data,
        };
    }
    pub fn deinit(self: *Form, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

const Record = struct {
    data: []u8,
};

const GenericBlock = extern struct {
    blockType: BlockTag,
    blockData: [126]u8,
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var alloc = gpa.allocator();

    const file = try std.fs.cwd().openFile("RESERVE.FOL", .{});

    var blockList = std.ArrayList(GenericBlock).init(alloc);
    defer blockList.deinit();

    var byteReader = file.reader();
    while (byteReader.readStruct(GenericBlock)) |block| {
        try blockList.append(block);
    } else |err| {
        if (err != error.EndOfStream) {
            return error.AHHHH;
        }
    }
    file.close();

    std.log.debug("Read {} blocks.\n", .{blockList.items.len});

    var form: Form = undefined;
    var head: Header = @bitCast(blockList.items[0]);

    var recordList = std.ArrayList(Record).init(alloc);
    defer recordList.deinit();

    for (blockList.items, 0..) |*block, i| {
        std.log.debug("Block {}: {any}\n", .{ i, block });

        switch (block.blockType) {
            .FormDescriptionView => {
                const numBlocks = std.mem.readIntSliceLittle(u16, block.blockData[0..2]);
                const lines = std.mem.readIntSliceBig(u16, block.blockData[4..6]);
                // const len = std.mem.readIntSliceBig(u16, block.blockData[2..4]);
                form = try Form.init(lines, 120 + numBlocks * 128, alloc);
                std.mem.copy(u8, form.data, &block.blockData);
                for (1..numBlocks) |j| {
                    std.mem.copy(u8, form.data[120 + (j - 1) * 128 ..], &block.blockData);
                }
            },
            .FormDescriptionContinuation => continue,
            .DataRecord => {
                const numBlocks = std.mem.readIntSliceLittle(u16, block.blockData[0..2]);
                var data = try alloc.alloc(u8, numBlocks * 128);
                defer alloc.free(data);

                for (0..numBlocks) |j| {
                    //todo: remember theres an extra byte in the first block that needs removed
                    std.mem.copy(u8, data, blockList.items[i + j].blockData[2..]);
                }
                try recordList.append(Record{ .data = data });
            },
            .DataContinuation => continue,
            else => {},
        }
    }
    std.debug.assert(head.dataRecords == recordList.items.len);
    std.debug.assert(form.data.len == form.length);

    defer form.deinit(alloc);
    std.log.debug("{any}\n", .{head});
    std.log.debug("{any} {} \n", .{ recordList, recordList.items.len });
}
