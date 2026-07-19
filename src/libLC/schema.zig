//! Schema (field definitions) parsed from the FormDescriptionView block and its
//! FormDescriptionContinuation blocks. All output is arena-owned.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Blocks = @import("blocks.zig");
const Text = @import("text.zig");
const value = @import("value.zig");
const Kind = value.Kind;

pub const FieldDef = struct {
    name: []const u8,
    kind: Kind,
};

pub const Schema = struct {
    fields: []const FieldDef,
    first_data_block: usize,
    lines_on_screen: u16 = 0,
    lines_length: u16 = 0,

    pub fn parse(
        allocator: Allocator,
        header: Blocks.Header,
        blocks: Blocks.BlockList,
    ) !Schema {
        const first_block = blocks[header.formDefinitionIndex];
        if (first_block.type != .FormDescriptionView) {
            std.log.err("expected FormDescriptionView at index {}", .{header.formDefinitionIndex});
            return error.InvalidBlockType;
        }
        const form = first_block.data.Schema.swapEndien();

        var field_data = try allocator.alloc(u8, form.num_blocks * Blocks.Block_Size);
        @memset(field_data, 0);
        field_data[0..form.data.len].* = form.data;
        var idx: usize = form.data.len;

        for (1..form.num_blocks) |i| {
            const next = blocks[header.formDefinitionIndex + i];
            if (next.type != .FormDescriptionContinuation) {
                std.log.err("expected FormDescriptionContinuation at index {}", .{header.formDefinitionIndex + i});
                return error.InvalidBlockType;
            }
            @memcpy(field_data[idx..][0..next.data.common.data.len], &next.data.common.data);
            idx += next.data.common.data.len;
        }

        const fields = try readFields(allocator, field_data[0..idx]);

        return .{
            .fields = fields,
            .first_data_block = header.formDefinitionIndex + form.num_blocks,
            .lines_on_screen = form.len_lines_on_screen,
            .lines_length = form.len_lines,
        };
    }

    fn readFields(allocator: Allocator, data: []const u8) ![]const FieldDef {
        var fields: std.ArrayList(FieldDef) = .empty;
        var bytes: ?[]const u8 = data;
        while (bytes) |d| {
            const name = try Text.initFromBytes(allocator, d);
            const kind = name.field_type orelse {
                std.log.err("schema field '{s}' has no type", .{name.asSlice()});
                return error.InvalidField;
            };
            try fields.append(allocator, .{ .name = name.asSlice(), .kind = kind });
            bytes = name.extra;
        }
        return fields.toOwnedSlice(allocator);
    }
};
