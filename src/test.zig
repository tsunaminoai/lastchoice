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
    pub fn logHex(self: *Form) void {
        for (self.data) |c| {
            if (c != 0) std.log.debug("{X}", .{c});
        }
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

    const file = try std.fs.cwd().openFile("ALUMNI.FOL", .{});

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
        // std.log.debug("Block {}: {any}\n", .{ i, block });

        switch (block.blockType) {
            .FormDescriptionView => {
                const numBlocks = std.mem.readIntSliceLittle(u16, block.blockData[0..2]);
                const lines = std.mem.readIntSliceBig(u16, block.blockData[4..6]);
                // const len = std.mem.readIntSliceBig(u16, block.blockData[2..4]);
                form = try Form.init(lines, 120 + numBlocks * 128, alloc);
                std.mem.copy(u8, form.data[0..120], block.blockData[6..]);
                for (0..numBlocks) |j| {
                    var idx = 120 + (j) * 128;
                    std.log.debug("IDX for form data insertion: {}\n", .{idx});
                    std.mem.copy(u8, form.data[idx..], &blockList.items[i + j].blockData);
                }
            },
            .FormDescriptionContinuation => continue,
            .DataRecord => {
                const numBlocks = std.mem.readIntSliceLittle(u16, block.blockData[0..2]);
                var data = try alloc.alloc(u8, numBlocks * 128);
                // defer alloc.free(data);

                for (0..numBlocks) |j| {
                    //todo: remember theres an extra byte in the first block that needs removed
                    std.mem.copy(u8, data, blockList.items[i + j].blockData[2..]);
                }
                try recordList.append(Record{ .data = data });
            },
            .DataContinuation => continue,
            else => {
                std.log.warn("Block type {X} not implemented\n", .{block.blockType});
            },
        }
    }
    std.debug.assert(head.dataRecords == recordList.items.len);
    std.debug.assert(form.data.len == form.length);

    defer form.deinit(alloc);
    std.log.debug("{any}\n", .{head});
    // std.log.debug("{any} {} \n", .{ recordList, recordList.items.len });
    // form.logHex();

    // var D = recordList.items[2];
    var D = form;

    var i: usize = 0;

    const Field = struct {
        fieldType: u8,
        fieldAttributes: CharacterAttributes = CharacterAttributes{},
    };
    var charList = std.ArrayList(TextChar).init(alloc);
    var fieldList = std.ArrayList(Field).init(alloc);
    defer charList.deinit();
    defer fieldList.deinit();

    full: while (i < D.data.len - 3) {
        //get size of text
        var size = std.mem.readIntSliceLittle(u16, D.data[i .. i + 2]);
        if (size == 0) break :full;
        i += 2;
        std.log.debug("size: {}\n", .{size});

        var j: usize = 0;
        while (j < size) {
            if (i + j >= D.data.len) break :full;
            const char = D.data[i + j];
            var newChar = TextChar{};
            switch (char) {
                0x0, 0x7F => {
                    // plain character, nothing more to do
                    j += 1;
                },
                0x0d => {
                    newChar.character = '\n';
                    j += 1;
                },
                else => |c| {
                    // handle multibyte
                    newChar.character = c & 0x7F;
                    const byte2 = D.data[i + j + 1];
                    switch (byte2) {
                        0xD0, 0xDF => {
                            //need 3rd byte for background text or field text
                            const byte3 = D.data[i + j + 2];
                            newChar.setAtttributes(byte2);
                            newChar.setAtttributes(byte3);

                            j += 3;
                        },
                        0x81, 0x8F => {
                            //normal text but with attrs
                            newChar.character = c & 0x7F;
                            newChar.setAtttributes(byte2);
                            j += 2;
                        },
                        0x90, 0x9F => {
                            std.log.debug("Two byte: 0x{X} char:{c} stripped: {c}, Valid tag? '{}'\n", .{ c, c, newChar.character, FieldTypeTag.isValid(c) });
                            if (FieldTypeTag.isValid(c)) {
                                var tag = @as(FieldTypeTag, @enumFromInt(c));
                                std.log.info("Field Type: {s}\n", .{@tagName(tag)});
                                //todo: do something with the tag
                            } else {
                                //field names
                                newChar.setAtttributes(byte2);
                            }

                            j += 2;
                        },
                        0xC0, 0xCF => {
                            //need 3rd byte for normal text
                            const byte3 = D.data[i + j + 2];
                            newChar.setAtttributes(byte2);
                            newChar.setAtttributes(byte3);

                            j += 3;
                        },
                        0x0D => {
                            newChar.character = '\n';
                            j += 2;
                        },
                        else => |x| {
                            //todo
                            std.log.warn("Found a weird byte2 at position {}: 0x{X} '{c}'", .{ i + j + 1, x, x });
                            j += 2;
                        },
                    }
                },
            }
            // std.log.debug("{}, {any}\n", .{ i, newChar });
            try charList.append(newChar);
        }

        i += j;
    }

    std.log.debug("Read in {} chars\n", .{charList.items.len});
    for (charList.items) |item| {
        std.debug.print("{c}", .{item.character});
    }
    std.log.debug("My record: {s}\n", .{std.fmt.fmtSliceEscapeUpper(D.data[0..126])});
    for (D.data) |x| {
        std.debug.print("{c}", .{x & 0x7F});
    }
    std.debug.print("\n", .{});

    std.log.debug(
        \\Size: {},{}
        \\String: {c}
        \\more1: {}
        \\spmething: {X}
    , .{
        D.data[0],                         D.data[1],
        D.data[2..3].*[0] & @as(u8, 0x7F), std.mem.readIntSliceBig(u16, D.data[3..5]),
        D.data[3],
        // std.fmt.bytesToHex(D.data[5..77], .upper),
        // std.mem.readIntSliceBig(u16, D.data[24..26]),
    });
    for (recordList.items) |*record| {
        alloc.free(record.data);
    }
}

const FieldTypeTag = enum(u8) {
    // General = ' ',
    // Numeric = 'N',
    // Date = 'D',
    // Time = 'T',
    // Bool = 'Y',
    Text = 0x81,
    Numeric = 0x82,
    Date = 0x83,
    Time = 0x84,
    Bool = 0x85,

    pub fn isValid(char: u8) bool {
        const fields = comptime @typeInfo(FieldTypeTag).Enum.fields;
        inline for (fields) |f| {
            if (char == f.value) return true;
        }
        return false;
    }
};

test "fieldtype" {
    try std.testing.expect(FieldTypeTag.isValid(0x81) == true);
    try std.testing.expect(FieldTypeTag.isValid(0x65) == false);
}

const ScriptState = enum { Normal, Super, Sub };
const CharacterAttributes = struct {
    underline: bool = false,
    bold: bool = false,
    italic: bool = false,
    script: ScriptState = .Normal,
};

const TextChar = struct {
    character: u8 = 0,
    attributes: CharacterAttributes = CharacterAttributes{},

    const Self = @This();

    pub fn setBold(self: *Self, checkByte: u8) void {
        self.attributes.bold = checkByte & 0x2 == 0x2;
    }
    pub fn setItalic(self: *Self, checkByte: u8) void {
        self.attributes.italic = checkByte & 0x4 == 0x4;
    }
    pub fn setUnderline(self: *Self, checkByte: u8) void {
        self.attributes.bold = checkByte & 0x1 == 0x1;
    }
    pub fn setSuper(self: *Self, checkByte: u8) void {
        if (checkByte & 0xFE == 0x84) {
            self.attributes.script = .Super;
        } else {
            self.attributes.script = .Normal;
        }
    }
    pub fn setSub(self: *Self, checkByte: u8) void {
        if (checkByte & 0xFE == 0x82) {
            self.attributes.script = .Sub;
        } else {
            self.attributes.script = .Normal;
        }
    }
    pub fn setAtttributes(self: *Self, maskByte: u8) void {
        self.setBold(maskByte);
        self.setItalic(maskByte);
        self.setUnderline(maskByte);
        self.setSuper(maskByte);
        self.setSub(maskByte);
    }
};
