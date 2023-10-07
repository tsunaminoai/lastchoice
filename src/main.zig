const std = @import("std");

const FCF = @This(); //FirstChoice File

const Allocator = std.mem.Allocator;

const bigToNative = std.mem.bigToNative;
const nativeToBig = std.mem.nativeToBig;

buffer: ?[]u8 = null,
index: usize = 0,
head: ?Header = null,
allocator: Allocator,
blocks: ?std.ArrayList(Block) = null,

const magicString = "\x0cGERBILDB3   \x00";
const extension = "FOL";

const Error = error{EndOfStream} || anyerror;

const Block = extern struct { recordType: RecordType, data: [126]u8 };

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

const RecordType = enum(u16) {
    DataRecord = 0x81,
    DataContinuation = 0x01,
    FormDescriptionView = 0x82,
    FormDescriptionContinuation = 0x02,
    TableView = 0x83,
    TableViewContinuation = 0x03,
    Formula = 0x84,
    FormulaContinuation = 0x04,
    Empty = 0x0,
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

    try self.read();
}

fn read(self: *FCF) Error!void {
    while (try self.peekBlock()) |blockType| {
        switch (blockType) {
            else => try self.blocks.?.append(try self.readStruct(Block)),
        }
    }
}

fn peekBlock(self: *FCF) Error!?RecordType {
    if (self.index + @sizeOf(Block) > self.buffer.?.len) return null;
    const tag = std.mem.readIntSlice(u16, self.buffer.?[self.index .. self.index + 2], std.builtin.Endian.Little);

    return @as(RecordType, @enumFromInt(tag));
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

pub fn deinit(self: *FCF) void {
    self.allocator.free(self.buffer.?);
    self.blocks.?.deinit();
    self.* = undefined;
}

test "Read header" {
    std.debug.assert(@sizeOf(Header) == 128);
    var alloc = std.testing.allocator;
    var fol = FCF.init(alloc);
    defer fol.deinit();

    try fol.open("RESERVE.FOL");
}
