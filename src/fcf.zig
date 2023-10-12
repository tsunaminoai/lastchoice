const std = @import("std");
const Header = @import("header.zig").Header;
pub usingnamespace @import("block.zig");
const Block = @import("block.zig");
const Empty = @import("block.zig").Empty;
const Form = @import("form.zig");

const Allocator = std.mem.Allocator;

const Endien = std.builtin.Endian;
const bigToNative = std.mem.bigToNative;
const nativeToBig = std.mem.nativeToBig;

buffer: []u8 = undefined,
index: usize = 0,
head: Header = undefined,
allocator: Allocator,
blocks: std.ArrayList(Block.Block) = undefined,
empties: std.ArrayList(Block.Empty) = undefined,
form: Form.Form = undefined,

const magicString = "\x0cGERBILDB3   \x00";
const extension = "FOL";

pub const FCF = @This(); //FirstChoice File

pub const Error = error{ EndOfStream, UnhandledBlockType, BadTextCharacter } || anyerror;

pub fn init(allocator: Allocator) FCF {
    _ = std.log.defaultLogEnabled(std.log.Level.debug);
    return .{
        .buffer = undefined,
        .head = undefined,
        .allocator = allocator,
    };
}

pub fn deinit(self: *FCF) void {
    self.allocator.free(self.buffer);
    for (self.blocks.items) |*b| {
        b.deinit(self.allocator);
    }
    self.blocks.deinit();
    self.form.deinit();
    // self.empties.deinit();
}

pub fn open(self: *FCF, fileName: []const u8) Error!void {
    const file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    self.buffer = try file.readToEndAlloc(self.allocator, 4 * 1024 * 1024);
    std.log.debug("Loaded {} bytes\n", .{self.buffer.len});
    self.head = Header.fromBytes(self.buffer[0..128]);
    self.head.print();

    // self.blocks = try std.ArrayList(Block).initCapacity(self.allocator, self.head.totalFileBlocks);
    self.blocks = try Block.readBlocks(self.buffer, self.allocator);
    // std.debug.assert(self.blocks.items.len == self.head.totalFileBlocks);
    std.log.debug("Read {} blocks", .{self.blocks.items.len});
    self.form = try Form.parseFormBlocks(self.blocks, self.head, self.allocator);
    // self.empties = try std.ArrayList(Empty).initCapacity(self.allocator, self.head.totalFileBlocks);
    // try self.readEmpties();
    // try self.read();

}

fn readEmpties(self: *FCF) Error!void {
    // move to the fifth block
    self.index = @sizeOf(Block) * 4;
    for (0..self.head.emptiesLength) |_| {
        try self.empties.append(try self.readStruct(Empty));
    }
}

fn read(self: *FCF) Error!void {
    std.log.debug("<read>", .{});

    self.index = @sizeOf(Block) * self.head.formDefinitionIndex;

    while (try Block.peekBlock(self)) |blockType| {
        switch (blockType) {
            .FormDescriptionView => try self.blocks.append(try self.readStruct(Block)),
            else => try self.blocks.append(try self.readStruct(Block)),
        }

        break;
    }
    std.log.debug("</read>", .{});
}

fn readStruct(self: *FCF, comptime T: type) Error!T {
    std.log.debug("<readStruct>", .{});

    const fields = std.meta.fields(T);

    var item: T = undefined;
    inline for (fields) |field| {
        @field(item, field.name) = try self.readStructField(field.type);
    }
    std.log.debug("</readStruct>", .{});

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
    if (self.index + size > self.buffer.len) return Error.EndOfStream;

    const slice = self.buffer[self.index .. self.index + size];
    const value = @as(*align(1) const T, @ptrCast(slice)).*;
    self.index += size;
    return value;
}

test "Read header" {
    std.debug.assert(@sizeOf(Header) == 128);
    var alloc = std.testing.allocator;
    var fol = FCF.init(alloc);
    defer fol.deinit();

    try fol.open("RESERVE.FOL");
    // try fol.parseBlocks();

    fol.form.print();
}
