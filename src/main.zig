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
form: ?Form = null,

const magicString = "\x0cGERBILDB3   \x00";
const extension = "FOL";

const Error = error{ EndOfStream, UnhandledBlockType, BadTextCharacter } || anyerror;

pub const Block = extern struct { recordType: BlockTypeInt, data: [126]u8 };
const Empty = extern struct { entry1: u16, entry2: u16 };

const BlockIndex = enum(u16) {
    None = 0xFFFF,
    _,
};

pub const Header = extern struct {
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

pub fn init(allocator: Allocator) FCF {
    _ = std.log.defaultLogEnabled(std.log.Level.debug);
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

    std.log.debug("Loaded {} bytes\n", .{self.buffer.?.len});
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
        std.log.debug(fmt, .{ head.formDefinitionIndex, head.lastUsedBlock, head.totalFileBlocks, head.dataRecords, head.availableDBFields, head.formLength, head.formRevisions, head.emptiesLength, head.tableViewIndex, head.programRecordIndex, head.nextFieldSize, head.diskVar });
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
        @field(item, field.name) = try self.readStructField(field.type);
    }
    return item;
}
fn readStructField(self: *FCF, comptime T: type) Error!T {
    return switch (@typeInfo(T)) {
        .Enum, .Int => try self.readInt(T),
        .Array => |array| {
            var arr: [array.len]array.child = undefined;
            var index: usize = 0;
            while (index < array.len) : (index += 1) {
                arr[index] = try self.readStructField(array.child);
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

const FieldType = enum(u8) {
    Text,
    Numeric,
    Date,
    Time,
    Bool,
    _,
    pub fn decode(byte: u8) FieldType {
        const check = byte & 0xF;
        std.log.debug("{X} -> {X}\n", .{ check, check });
        if (byte & 0x80 == 0x80) {
            return @as(FieldType, @enumFromInt(byte & 0xF));
        } else {
            return @as(FieldType, @enumFromInt(byte));
        }
    }
};

const TextStyles = packed struct(u8) {
    normal: bool = false,
    underline: bool = false,
    bold: bool = false,
    italic: bool = false,
    _padding: enum(u4) { unset } = .unset,
};

const Baseline = packed struct(u8) {
    normalBackground: bool = false,
    sub: bool = false,
    subBackground: bool = false,
    super: bool = false,
    superBackground: bool = false,
    _padding: enum(u3) { unset } = .unset,
};

const TextCharacter = struct {
    char: u8 = 0,
    style: TextStyles = TextStyles{},
    baseline: Baseline = Baseline{},
};

const Field = struct {
    fieldType: FieldType = FieldType.Text,
    fieldStyle: TextStyles = TextStyles{},
    name: std.ArrayList(TextCharacter) = undefined,

    pub fn print(self: *@This()) void {
        std.log.debug("Field: ", .{});

        for (self.name.items) |char| {
            std.log.debug("{c}", .{char.char});
        }
        std.log.debug(" : {s} ({any})\n", .{ @tagName(self.fieldType), self.fieldStyle });
    }

    pub fn deinit(self: *@This()) void {
        self.name.deinit();
    }
};

fn decodeField(self: *FCF, bytes: []const u8, size: usize) !Field {
    return Field{
        .fieldType = FieldType.decode(bytes[0]),
        .fieldStyle = @as(TextStyles, @bitCast(bytes[1] & 0xF)),
        .name = try self.decodeText(bytes[2..], size),
    };
}

fn decodeText(self: *FCF, bytes: []const u8, size: usize) !std.ArrayList(TextCharacter) {
    var idx: usize = 0;
    _ = size;

    var string = std.ArrayList(TextCharacter).init(self.allocator);
    errdefer string.deinit();

    while (idx < bytes.len - 1) {
        var newChar = TextCharacter{};

        if (bytes[idx] & 0x80 == 0x80) {
            if (bytes[idx] == 0x80) newChar.char = ' ' else newChar.char = bytes[idx] & 0x7F;

            if (bytes[idx + 1] & 0xD0 == 0xD0) {
                newChar.baseline = @as(Baseline, @bitCast(bytes[idx + 2] & 0xF));
                try string.append(newChar);
                idx += 3;
            } else {
                newChar.style = @as(TextStyles, @bitCast(bytes[idx + 1] & 0xF));
                try string.append(newChar);
                idx += 2;
            }
        } else {
            newChar.char = bytes[0];
            try string.append(newChar);
            idx += 1;
        }
    }

    // std.log.info("String: {any}", .{string});
    return string;
}

const Form = struct {
    fields: std.ArrayList(Field) = undefined,
    numBlocks: u16 = 0,
    lines: u16 = 0,
    length: u16 = 0,

    pub fn deinit(self: *@This()) void {
        for (self.fields.items) |*f| {
            f.deinit();
        }
        self.fields.deinit();
    }

    pub fn print(self: *@This()) void {
        const fmt =
            \\
            \\Form Length: {}
            \\Form Block Length: {}
            \\Form Lines: {}
            \\Form Fields: {}
            \\
        ;
        std.log.debug(fmt, .{ self.length, self.numBlocks, self.lines, self.fields.items.len });
    }
};

fn readForm(self: *FCF, b: Block) !Form {
    var form = Form{
        .numBlocks = std.mem.readInt(u16, b.data[0..2], Endien.Little),
        .lines = std.mem.readInt(u16, b.data[2..4], Endien.Big),
        .length = std.mem.readInt(u16, b.data[4..6], Endien.Big),
    };

    var fields = std.ArrayList(Field).init(self.allocator);
    var tok = std.mem.tokenizeAny(u8, b.data[6..], "\x0d");

    while (tok.next()) |t| {
        const num = std.mem.readIntSliceBig(u16, t[0..2]);
        // const textBytes = t[2..];
        var strippedBytes = try self.allocator.alloc(u8, t.len - 2);
        defer self.allocator.free(strippedBytes);

        var f = try self.decodeField(t, num);

        try fields.append(f);
    }
    form.fields = fields;
    return form;
}

fn parseBlocks(self: *FCF) !void {
    for (self.blocks.?.items) |b| {
        switch (b.recordType) {
            .FormDescriptionView => {
                self.form = try self.readForm(b);
            },
            else => {},
        }
    }
}

pub fn deinit(self: *FCF) void {
    self.allocator.free(self.buffer.?);
    self.blocks.?.deinit();
    self.form.?.deinit();
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

    fol.form.?.print();
}
