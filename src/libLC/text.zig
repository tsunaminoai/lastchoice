//! Internal parse helper for FirstChoice's length-prefixed text encoding.
//!
//! On-disk each text field is a big-endian u16 length followed by that many
//! bytes. Bytes < 0x80 are literal ASCII. A byte >= 0x80 is a styled character:
//! `(char | 0x80)` followed by a marker byte, and for a couple of marker ranges
//! a further attribute byte. The marker high nibble categorises the run:
//!
//!   0x8x  normal text            (2 bytes: char, marker)
//!   0x9x  form field name/type   (2 bytes: char, marker) -- schema text only
//!   0xCx  attributed text        (3 bytes: char, marker, attr)
//!   0xDx  background/field text  (3 bytes: char, marker, attr)
//!
//! In the 0x9x range the terminating character of a schema field encodes the
//! field's `Kind` in its low nibble instead of a printable character.
//!
//! The exact bold/underline/italic bit layout of the 0xCx/0xDx marker+attr
//! bytes is not confirmed (neither bundled fixture contains styled record
//! text), so those bytes are preserved verbatim on each emitted `StyleRun`.
//! TODO(zig-0.16-migration): confirm style bit semantics against styled data.

const std = @import("std");
const Allocator = std.mem.Allocator;
const value = @import("value.zig");
const Kind = value.Kind;
const Style = value.Style;
const StyleRun = value.StyleRun;
const StyledText = value.StyledText;

const Text = @This();

/// Decoded characters (arena-owned).
string: std.ArrayList(u8),
/// Per-character formatting, parallel to `string`.
styles: std.ArrayList(CharStyle),
allocator: Allocator,
/// The field type, if this text was a schema field definition.
field_type: ?Kind = null,
/// The remaining bytes after this field, or null if none remain.
extra: ?[]const u8 = null,

const CharStyle = struct {
    style: Style,
    marker: u8 = 0,

    fn eql(a: CharStyle, b: CharStyle) bool {
        return a.marker == b.marker and a.style.eql(b.style);
    }

    fn isDefault(self: CharStyle) bool {
        return self.marker == 0 and self.style.isDefault();
    }
};

/// Parses a single length-prefixed text field from `data`. All output is
/// allocated with `allocator` (expected to be an arena).
///
/// The leading big-endian u16 is a display width, not a reliable byte count, so
/// it is used only for validation. The authoritative field boundary is the
/// first `0x00` low byte: content runs up to it, and that same byte doubles as
/// the high byte of the following field's length prefix (field lengths are
/// always < 256). Trailing 0x20/0x0d padding is folded into spaces and trimmed.
pub fn initFromBytes(allocator: Allocator, data: []const u8) !Text {
    var self: Text = .{
        .string = .empty,
        .styles = .empty,
        .allocator = allocator,
    };

    if (data.len < 2) return error.InvalidLength;
    const slice = data[2..];

    var i: usize = 0;
    var content_end: usize = slice.len;
    while (i < slice.len) {
        const char = slice[i];
        if (char == 0) {
            content_end = i;
            break;
        }
        i += 1;
        if (char < 0x80) {
            if (char == 0x0d) {
                try self.addChar(' ', .{ .style = .{} });
            } else {
                try self.addChar(char, .{ .style = .{} });
            }
        } else {
            const stripped = char & 0x7f;
            if (i >= slice.len) break;
            const marker = slice[i];
            i += 1;
            switch (marker) {
                0x81...0x8f => try self.addChar(stripped, .{ .style = .{} }),
                0x90...0x9f => {
                    if (Kind.fromInt(stripped)) |kind| {
                        self.field_type = kind;
                    } else {
                        try self.addChar(
                            if (stripped == 0) ' ' else stripped,
                            .{ .style = .{ .field = true }, .marker = marker },
                        );
                    }
                },
                0xc0...0xcf => {
                    if (i >= slice.len) break;
                    const attr = slice[i];
                    i += 1;
                    try self.addChar(stripped, decodeAttr(marker, attr));
                },
                0xd0...0xdf => {
                    if (i >= slice.len) break;
                    const attr = slice[i];
                    i += 1;
                    var cs = decodeAttr(marker, attr);
                    cs.style.background = true;
                    try self.addChar(stripped, cs);
                },
                else => {
                    std.log.warn("unknown text marker 0x{X} (char 0x{X})", .{ marker, char });
                    return error.UnknownCharacter;
                },
            }
        }
    }

    self.trim();

    // The next field begins at the terminating 0x00. If the length there is 0
    // (all-zero padding), this was the last field.
    const rest = slice[content_end..];
    if (rest.len >= 2 and std.mem.readInt(u16, rest[0..2], .big) != 0) {
        self.extra = rest;
    }
    return self;
}

/// Best-effort decode of the 0xCx/0xDx marker+attr bytes. The precise bit
/// layout is unconfirmed, so the raw marker is preserved on the resulting run
/// and only the low marker-nibble bits (a plausible bold/underline guess) are
/// surfaced as flags.
fn decodeAttr(marker: u8, attr: u8) CharStyle {
    _ = attr;
    return .{
        .style = .{
            .bold = (marker & 0x01) != 0,
            .underline = (marker & 0x02) != 0,
        },
        .marker = marker,
    };
}

fn addChar(self: *Text, char: u8, cs: CharStyle) !void {
    try self.string.append(self.allocator, char);
    try self.styles.append(self.allocator, cs);
}

fn trim(self: *Text) void {
    while (self.string.items.len > 0 and self.string.getLast() == ' ') {
        _ = self.string.pop();
        _ = self.styles.pop();
    }
    while (self.string.items.len > 0 and self.string.items[0] == ' ') {
        _ = self.string.orderedRemove(0);
        _ = self.styles.orderedRemove(0);
    }
}

/// The decoded characters as a slice (arena-owned, stable).
pub fn asSlice(self: Text) []const u8 {
    return self.string.items;
}

/// Builds a `StyledText` (text + RLE runs). All-default runs are omitted.
pub fn toStyledText(self: Text, allocator: Allocator) !StyledText {
    var runs: std.ArrayList(StyleRun) = .empty;
    var i: usize = 0;
    while (i < self.styles.items.len) {
        const cs = self.styles.items[i];
        var j = i + 1;
        while (j < self.styles.items.len and self.styles.items[j].eql(cs)) : (j += 1) {}
        if (!cs.isDefault()) {
            try runs.append(allocator, .{
                .start = @intCast(i),
                .len = @intCast(j - i),
                .style = cs.style,
                .marker = cs.marker,
            });
        }
        i = j;
    }
    return .{ .text = self.string.items, .runs = try runs.toOwnedSlice(allocator) };
}

test "Text decodes a schema field name and kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = [_]u8{
        0x00, 0x32, 0xc6, 0x90, 0xe9, 0x90, 0xf2, 0x90,
        0xf3, 0x90, 0xf4, 0x90, 0x80, 0x90, 0xee, 0x90,
        0xe1, 0x90, 0xed, 0x90, 0xe5, 0x90, 0x81, 0x90,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x20, 0x20, 0x20, 0x20,
    };
    const t = try Text.initFromBytes(a, &bytes);
    try std.testing.expectEqualStrings("First name", t.asSlice());
    try std.testing.expectEqual(Kind.general, t.field_type.?);
}

test "unstyled text yields no runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = [_]u8{ 0x00, 0x07, 0x20, 0x20, 'H', 'e', 'l', 'l', 'o' };
    const t = try Text.initFromBytes(a, &bytes);
    const styled = try t.toStyledText(a);
    try std.testing.expectEqualStrings("Hello", styled.text);
    try std.testing.expectEqual(@as(usize, 0), styled.runs.len);
}
