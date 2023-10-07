const std = @import("std");

const FCF = @This(); //FirstChoice File

const Allocator = std.mem.Allocator;
const Endien = std.builtin.Endian;

const bigToNative = std.mem.bigToNative;
const nativeToBig = std.mem.nativeToBig;

buffer: ?[]u8 = null,
index: usize = 0,
head: ?Header = null,
allocator: Allocator,
blocks: ?std.ArrayList(Block) = null,
empties: ?std.ArrayList(Empty) = null,

const magicString = "\x0cGERBILDB3   \x00";
const extension = "FOL";

const Error = error{ EndOfStream, UnhandledBlockType, BadTextCharacter } || anyerror;

const Block = extern struct { recordType: BlockTypeInt, data: [126]u8 };
const Empty = extern struct { entry1: u16, entry2: u16 };

const BlockIndex = enum(u16) {
    None = 0xFFFF,
    _,
};

const Header = extern struct {
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
    tableViewIndex: BlockIndex,
    programRecordIndex: BlockIndex,
    _2: u16,
    _3: u16,
    nextFieldSize: u8,
    diskVar: [128 - 41]u8,
};

const BlockTypeInt = enum(u16) {
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

pub fn init(allocator: Allocator) FCF {
    return .{
        .buffer = undefined,
        .head = undefined,
        .allocator = allocator,
    };
}

pub fn open(
    self: *FCF,
    fileName: []const u8,
) Error!void {
    const file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    self.buffer = try file.readToEndAlloc(self.allocator, 4 * 1024 * 1024);
    self.head = try self.readStruct(Header);

    std.debug.print("Loaded {} bytes\n", .{self.buffer.?.len});
    const fmt =
        \\
        \\Form Index: {}
        \\Last Block: {}
        \\Total Blocks: {}
        \\Data Records: {}
        \\Available Fields: {}
        \\Form Length: {}
        \\Form Revisions: {}
        \\Empties Length: {}
        \\Table Index: {}
        \\Program Index: {}
        \\Next Field Size: {}
        \\@DISKVAR: "{s}"
        \\
    ;
    if (self.head) |head| {
        std.debug.print(fmt, .{ head.formDefinitionIndex, head.lastUsedBlock, head.totalFileBlocks, head.dataRecords, head.availableDBFields, head.formLength, head.formRevisions, head.emptiesLength, head.tableViewIndex, head.programRecordIndex, head.nextFieldSize, head.diskVar });
    }
    self.blocks = try std.ArrayList(Block).initCapacity(self.allocator, self.head.?.totalFileBlocks);
    self.empties = try std.ArrayList(Empty).initCapacity(self.allocator, self.head.?.totalFileBlocks);
    try self.readEmpties();
    try self.read();
}

fn readEmpties(self: *FCF) Error!void {
    // move to the fifth block
    self.index = @sizeOf(Block) * 4;
    for (0..self.head.?.emptiesLength) |_| {
        try self.empties.?.append(try self.readStruct(Empty));
    }
}

fn read(self: *FCF) Error!void {
    self.index = @sizeOf(Block) * self.head.?.formDefinitionIndex;

    while (try self.peekBlock()) |blockType| {
        switch (blockType) {
            .FormDescriptionView => try self.blocks.?.append(try self.readStruct(Block)),
            else => try self.blocks.?.append(try self.readStruct(Block)),
        }
    }
}

fn peekBlock(self: *FCF) Error!?BlockTypeInt {
    if (self.index + @sizeOf(Block) > self.buffer.?.len) return null;
    const tagInt = std.mem.readIntSlice(u16, self.buffer.?[self.index + 1 .. self.index + 3], std.builtin.Endian.Little);
    const tag = @as(BlockTypeInt, @enumFromInt(tagInt));

    return tag;
}

fn readStruct(self: *FCF, comptime T: type) Error!T {
    const fields = std.meta.fields(T);

    var item: T = undefined;
    inline for (fields) |field| {
        @field(item, field.name) = try self.readField(field.type);
    }
    return item;
}
fn readField(self: *FCF, comptime T: type) Error!T {
    return switch (@typeInfo(T)) {
        .Enum, .Int => try self.readInt(T),
        .Array => |array| {
            var arr: [array.len]array.child = undefined;
            var index: usize = 0;
            while (index < array.len) : (index += 1) {
                arr[index] = try self.readField(array.child);
            }
            return arr;
        },
        .Struct => try self.readStruct(T),
        else => @compileError("Unimplemented type: " ++ @typeName(T)),
    };
}

fn readInt(self: *FCF, comptime T: type) Error!T {
    const size = @sizeOf(T);
    if (self.index + size > self.buffer.?.len) return Error.EndOfStream;

    const slice = self.buffer.?[self.index .. self.index + size];
    const value = @as(*align(1) const T, @ptrCast(slice)).*;
    self.index += size;
    return value;
}

const Field = struct {};
fn readFields(self: *FCF, data: *align(2) const [120]u8) !Field {
    var fieldList = std.ArrayList(Field).init(self.allocator);
    _ = fieldList;
    var i: usize = 0;
    while (i < data.len) {
        const size = std.mem.readInt(u16, data[0..2], Endien.Big);
        i += 2;

        var j: usize = 0;
        while (j < size) {
            var idx = i + j;
            switch (data[idx]) {
                // carriage return
                0x13 => |char| {
                    std.debug.print("{c}", .{char});
                    j += 2;
                },
                // ascii 1 byte
                0x00, 0x7F => |char| {
                    std.debug.print("{c}", .{char});
                    j += 1;
                },
                0x80, 0x85 => |char| {
                    std.debug.print("{c}", .{char});
                    // handle two byte
                    switch (data[idx + 1]) {
                        0x90, 0x94 => {
                            std.debug.print("{x}", .{char});
                        },
                        else => unreachable,
                    }
                    j += 2;
                },
                else => {
                    std.debug.print("Unknown text byte: {X}\n", .{data[idx]});
                    j += 1;
                    continue;
                },
            }
        }
        std.debug.print("{any}\n", .{data[i]});
    }
    return Field{};
}
const Form = struct {
    fields: []Field,
    numBlocks: u16,
    lines: u16,
    length: u16,
    data: Field,
};

fn readForm(self: *FCF, b: Block) !Form {
    return Form{
        .fields = &[_]Field{},
        .numBlocks = std.mem.readInt(u16, b.data[0..2], Endien.Little),
        .lines = std.mem.readInt(u16, b.data[2..4], Endien.Big),
        .length = std.mem.readInt(u16, b.data[4..6], Endien.Big),
        .data = try self.readFields(b.data[6..]),
    };
}

fn parseBlocks(self: *FCF) !void {
    for (self.blocks.?.items) |b| {
        switch (b.recordType) {
            .FormDescriptionView => {
                const form = self.readForm(b);
                std.debug.print("{any}\n", .{form});
            },
            else => {},
        }
    }
}

pub fn deinit(self: *FCF) void {
    self.allocator.free(self.buffer.?);
    self.blocks.?.deinit();
    self.empties.?.deinit();
    self.* = undefined;
}

test "Read header" {
    std.debug.assert(@sizeOf(Header) == 128);
    var alloc = std.testing.allocator;
    var fol = FCF.init(alloc);
    defer fol.deinit();

    try fol.open("RESERVE.FOL");
    try fol.parseBlocks();
}
