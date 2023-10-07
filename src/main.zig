const std = @import("std");
const bigEndien = std.mem.bigToNative;
const testing = std.testing;

const magicString = "\x0cGERBILDB3   \x00";
const extension = "FOL";

// zig fmt: off
const RecordType = enum(u16) {
    DataRecord = 0x81,
    DataContinuation = 0x01,
    FormDescriptionView = 0x82,
    FormDescriptionContinuation = 0x02,
    TableView = 0x83,
    TableViewContinuation = 0x03,
    Formula = 0x84,
    FormulaContinuation = 0x04
};

const CharacterSize = enum(u3) {
    OneByte = 1,
    TwoByte = 2,
    ThreeByte = 3,
};


// zig fmt: on

const BlockIndex = enum(u16) {
    None = 0xFFFF,
};

const Block = struct { data: [128]u8 };

const FormDescriptionRecord = struct {
    recordType: RecordType,
    totalBlocks: u16,
    linesInScreen: u16, //BE
    length: u16, //BE len+lines+1
    fields: [120]u8,
};

const Header = struct {
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

const Reader = struct {
    bytes: []const u8,
    index: usize,

    const Errors = error{
        EndOfStream,
    };
    pub fn init(bytes: []const u8) Reader {
        return .{ .bytes = bytes, .index = 0 };
    }

    pub fn read(self: *Reader, comptime T: type) Errors!T {
        return switch (@typeInfo(T)) {
            .Enum, .Int => try self.readInt(T),
            .Array => |array| {
                var arr: [array.len]array.child = undefined;
                var index: usize = 0;
                while (index < array.len) : (index += 1) {
                    arr[index] = try self.read(array.child);
                }
                return arr;
            },
            .Struct => try self.readStruct(T),
            else => @compileError("Unimplemented type: " ++ @typeName(T)),
        };
    }

    fn readInt(self: *Reader, comptime T: type) Errors!T {
        const size = @sizeOf(T);
        if (self.index + size > self.bytes.len) return Errors.EndOfStream;

        const slice = self.bytes[self.index .. self.index + size];
        const value = @as(*align(1) const T, @ptrCast(slice)).*;
        self.index += size;
        return value;
    }

    fn readStruct(self: *Reader, comptime T: type) Errors!T {
        const fields = std.meta.fields(T);

        var item: T = undefined;
        inline for (fields) |field| {
            @field(item, field.name) = try self.read(field.type);
        }
        return item;
    }
};

pub fn openFOL(fileName: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    const read_buffer = try file.readToEndAlloc(allocator, 1024 * 1024);

    std.debug.print("Loaded {} bytes\n", .{read_buffer.len});

    return read_buffer;
}

test "Header sanity" {
    try testing.expectEqual(@sizeOf(Header), @sizeOf(Block));
}

test "Open FOL File" {
    var gpa = testing.allocator;
    var file = try openFOL("RESERVE.FOL", gpa);
    defer gpa.free(file);

    var reader = Reader.init(file);
    std.debug.print("Read in {} bytes\n", .{reader.bytes.len});
    const header = try reader.read(Header);
    std.debug.print("{any}\n", .{header});
    while (reader.read(Block)) |b| {
        std.debug.print("{any}\n", .{b});
    } else |err| {
        try testing.expect(err == error.EndOfStream);
    }
}
