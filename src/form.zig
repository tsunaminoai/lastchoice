const std = @import("std");
const FCF = @import("fcf.zig");
const Field = @import("field.zig");
const Block = @import("block.zig");
const Header = @import("header.zig");

const Endien = std.builtin.Endian;

pub const Form = struct {
    fields: std.ArrayList(Field.Field) = undefined,
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

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;
        const stringFormat =
            \\
            \\Form Length: {}
            \\Form Block Length: {}
            \\Form Lines: {}
            \\Form Fields: {}
            \\
        ;
        return std.fmt.format(writer, stringFormat, .{ self.length, self.numBlocks, self.lines, self.fields.items.len });
    }
};

fn readForm(b: Block.Block, alloc: std.mem.Allocator) !Form {
    std.log.debug("<readForm>", .{});
    var form = Form{
        .numBlocks = std.mem.readInt(u16, b.data[0..2], Endien.Little),
        .lines = std.mem.readInt(u16, b.data[2..4], Endien.Big),
        .length = std.mem.readInt(u16, b.data[4..6], Endien.Big),
    };

    var fields = std.ArrayList(Field.Field).init(alloc);
    var tok = std.mem.tokenizeAny(u8, b.data[6..], "\x0d");

    while (tok.next()) |t| {
        const num = std.mem.readIntSliceBig(u16, t[0..2]);
        // const textBytes = t[2..];
        var strippedBytes = try alloc.alloc(u8, t.len - 2);
        defer alloc.free(strippedBytes);

        var f = try Field.decodeField(t, num, alloc);

        try fields.append(f);
    }
    form.fields = fields;
    std.log.debug("</readForm>", .{});

    return form;
}

pub fn parseFormBlocks(blocks: std.ArrayList(Block.Block), header: Header.Header, alloc: std.mem.Allocator) !void {
    var formData: []u8 = try alloc.alloc(u8, header.formLength);
    defer alloc.free(formData);

    var idx: usize = 0;
    for (blocks.items[header.formDefinitionIndex..]) |b| {
        switch (b.recordType) {
            .FormDescriptionView, .FormDescriptionContinuation => {
                var f = try readForm(b, alloc);
                defer f.deinit();
                std.log.debug("{any}", .{f});
                std.mem.copy(u8, formData.ptr[idx..b.data.len], b.data);
            },
            else => {},
        }
    }
}
