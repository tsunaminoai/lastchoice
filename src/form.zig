const std = @import("std");
const FCF = @import("fcf.zig");
const Field = @import("field.zig");
const Block = @import("block.zig");

const Endien = std.builtin.Endian;

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
