const std = @import("std");
const Text = @import("text.zig");

pub const TypeTag = enum(u8) {
    General = 1,
    Numeric = 2,
    Date = 3,
    Time = 4,
    Bool = 5,
    pub fn fromInt(int: u8) ?TypeTag {
        switch (int) {
            1 => return .General,
            2 => return .Numeric,
            3 => return .Date,
            4 => return .Time,
            5 => return .Bool,
            else => return null,
        }
    }
};

pub const Type = union(TypeTag) {
    General: ?Text,
    Numeric: f32,
    Date: u32,
    Time: f32,
    Bool: bool,

    pub fn tagToType(tag: TypeTag) type {
        return switch (tag) {
            .General => ?Text,
            .Numeric => f32,
            .Date => u32,
            .Time => f32,
            .Bool => bool,
        };
    }
};

pub fn Field(comptime Tag: TypeTag) type {
    const T = Type.tagToType(Tag);
    const f = struct {
        name: *Text,
        values: std.ArrayList(T),
        type: TypeTag = Tag,

        const F = @This();

        var alloc: std.mem.Allocator = undefined;

        pub fn init(allocator: std.mem.Allocator, name: *Text) !F {
            alloc = allocator;
            return F{
                .name = name,
                .values = std.ArrayList(T).init(alloc),
            };
        }
        pub fn deinit(self: F) void {
            self.values.deinit();
            self.name.deinit();
        }
    };

    return f;
}
