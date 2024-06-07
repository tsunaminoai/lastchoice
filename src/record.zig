const std = @import("std");
const Field = @import("field.zig");
/// A record has a list of fields, which are the actual data
id: u32,

fields: std.ArrayList(Field.Definition),
