pub const Blocks = @import("blocks.zig");
pub const File = @import("file.zig");
pub const Schema = @import("schema.zig");

test {
    _ = @import("blocks.zig");
    _ = @import("field.zig");
    _ = @import("file.zig");
    _ = @import("fol.zig");
    _ = @import("schema.zig");
    _ = @import("text.zig");
}
