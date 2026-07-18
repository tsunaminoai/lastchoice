//! Public surface of the `lc` library: a typed reader for FirstChoice `.FOL`
//! databases. Consumers (CLI, exporters, TUI) depend only on this module.

const blocks = @import("blocks.zig");
const value = @import("value.zig");
const schema = @import("schema.zig");

/// The parsed file. See file.zig for init/initFromBytes/deinit/print.
pub const File = @import("file.zig");

pub const Header = blocks.Header;
pub const Block = blocks.Block;
pub const BlockKind = blocks.Kind;

pub const Schema = schema.Schema;
pub const FieldDef = schema.FieldDef;

pub const Kind = value.Kind;
pub const Value = value.Value;
pub const Record = value.Record;
pub const Date = value.Date;
pub const StyledText = value.StyledText;
pub const StyleRun = value.StyleRun;
pub const Style = value.Style;

test {
    _ = @import("blocks.zig");
    _ = @import("value.zig");
    _ = @import("text.zig");
    _ = @import("schema.zig");
    _ = @import("file.zig");
}
