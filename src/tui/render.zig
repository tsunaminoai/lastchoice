//! Pure renderer for the terminal browser. `draw` is a function of the current
//! `vaxis.Window` and a `*const AppState`: it reads state and paints cells, and
//! never mutates state or parses anything. All parsing lives in the `lc`
//! module; this file only knows how to lay typed records onto a grid.
//!
//! Cell lifetime: `vaxis.Window.writeCell` stores the grapheme *slice*, not a
//! copy, so every byte painted must stay valid until `vx.render()` runs back in
//! main. Field names and cell text are arena-owned by the `lc.File` (stable for
//! the whole session); the few formatted strings (numbers, dates, headers) are
//! duped into the caller-owned `frame_buf`, which also outlives the frame.

const std = @import("std");
const vaxis = @import("vaxis");
const lc = @import("lc");

/// Minimum usable terminal size; below this we show a fallback message.
pub const MIN_W = 40;
pub const MIN_H = 10;

/// Width of the fixed left schema pane (including its separator column).
const LEFT_W = 24;
/// Upper bound on any single main-pane column width.
const MAX_COL = 22;
/// Gap (in cells) between adjacent table columns.
const COL_GAP = 1;

/// Everything the browser tracks. Owned and mutated by main.zig; the renderer
/// only ever reads it.
pub const AppState = struct {
    file: lc.File,
    /// Input path, used for the status line and the export basename.
    path: []const u8,
    /// Index of the first record row shown in the main pane (vertical scroll).
    top_row: usize = 0,
    /// Index of the highlighted record.
    cursor_row: usize = 0,
    /// Index of the first schema field shown in the main pane (horizontal
    /// scroll), in whole columns.
    col_off: usize = 0,
    status_buf: [256]u8 = undefined,
    status_len: usize = 0,

    pub fn status(self: *const AppState) []const u8 {
        return self.status_buf[0..self.status_len];
    }

    pub fn setStatus(self: *AppState, comptime fmt: []const u8, args: anytype) void {
        const out = std.fmt.bufPrint(&self.status_buf, fmt, args) catch self.status_buf[0..0];
        self.status_len = out.len;
    }
};

pub fn draw(win: vaxis.Window, st: *const AppState, frame_buf: []u8) void {
    win.clear();
    var fba = std.heap.FixedBufferAllocator.init(frame_buf);
    const fa = fba.allocator();

    if (win.width < MIN_W or win.height < MIN_H) {
        put(win, 0, win.height / 2, "TERMINAL TOO SMALL", .{ .bold = true });
        return;
    }

    drawSchema(win, st);
    drawTable(win, st, fa);
    drawStatus(win, st, fa);
}

// ── left schema pane ─────────────────────────────────────────────────────────

fn drawSchema(win: vaxis.Window, st: *const AppState) void {
    put(win, 0, 0, "SCHEMA", .{ .bold = true });
    const bottom = win.height -| 1; // leave the status row alone
    for (st.file.schema.fields, 0..) |field, i| {
        const row = i + 1;
        if (row >= bottom) break;
        const selected = i == st.col_off;
        const style: vaxis.Style = .{ .bold = selected, .reverse = selected };
        putTrunc(win, 0, @intCast(row), field.name, LEFT_W - 6, style);
        put(win, LEFT_W - 5, @intCast(row), kindTag(field.kind), .{ .dim = true });
    }
    // Vertical separator between the panes.
    var r: u16 = 0;
    while (r < bottom) : (r += 1) put(win, LEFT_W - 1, r, "\u{2502}", .{ .dim = true });
}

fn kindTag(kind: lc.Kind) []const u8 {
    return switch (kind) {
        .general => "GEN",
        .numeric => "NUM",
        .date => "DAT",
        .time => "TIM",
        .boolean => "BOO",
    };
}

// ── main record table ────────────────────────────────────────────────────────

fn drawTable(win: vaxis.Window, st: *const AppState, fa: std.mem.Allocator) void {
    const fields = st.file.schema.fields;
    const records = st.file.records;
    const x0 = LEFT_W + 1;
    const bottom = win.height -| 1; // status row
    const visible_rows = bottom -| 1; // header row

    // Column widths, derived from the field name and the widths of visible
    // record cells, capped at MAX_COL.
    const widths = fa.alloc(usize, fields.len) catch return;
    for (fields, 0..) |field, f| {
        var w = field.name.len;
        var r = st.top_row;
        while (r < records.len and r < st.top_row + visible_rows) : (r += 1) {
            const s = cellDisplay(fa, records[r].cells[f]) catch "";
            w = @max(w, s.len);
        }
        widths[f] = @min(@max(w, 1), MAX_COL);
    }

    // Header row of field names.
    paintRow(win, st, x0, 0, widths, .{ .bold = true }, true, 0);

    // Record rows.
    var i: usize = 0;
    while (i < visible_rows) : (i += 1) {
        const rec = st.top_row + i;
        if (rec >= records.len) break;
        const highlighted = rec == st.cursor_row;
        const base: vaxis.Style = if (highlighted) .{ .reverse = true } else .{};
        paintRow(win, st, x0, @intCast(i + 1), widths, base, false, rec);
    }
}

/// Paints one table row. When `header` is true it paints field names; otherwise
/// it paints record `rec`'s cells. `x0`/`y` are cell coordinates.
fn paintRow(
    win: vaxis.Window,
    st: *const AppState,
    x0: u16,
    y: u16,
    widths: []const usize,
    base: vaxis.Style,
    header: bool,
    rec: usize,
) void {
    var fba_buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fba_buf);
    const fa = fba.allocator();

    var x: u16 = x0;
    var f = st.col_off;
    while (f < widths.len) : (f += 1) {
        if (x >= win.width) break;
        const colw = widths[f];
        if (header) {
            putTrunc(win, x, y, st.file.schema.fields[f].name, colw, base);
        } else {
            fba.reset();
            const cell = st.file.records[rec].cells[f];
            const text = cellDisplay(fa, cell) catch "?";
            paintStyledCell(win, x, y, text, cell, colw, base);
        }
        x += @intCast(colw + COL_GAP);
    }
}

/// Paints a cell's text, applying any style runs (bold/underline/italic) on top
/// of the row's base style. Fixtures carry no runs, so in practice this reduces
/// to a plain truncated write, but the run path is exercised structurally.
fn paintStyledCell(
    win: vaxis.Window,
    x: u16,
    y: u16,
    text: []const u8,
    cell: ?lc.Value,
    maxw: usize,
    base: vaxis.Style,
) void {
    const runs = cellRuns(cell);
    if (runs.len == 0) {
        putTrunc(win, x, y, text, maxw, base);
        return;
    }
    var col: u16 = x;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var painted: usize = 0;
    while (it.i < text.len and painted < maxw) : (painted += 1) {
        const start = it.i;
        _ = it.nextCodepoint() orelse break;
        putCell(win, col, y, text[start..it.i], mergeStyle(base, runs, start));
        col += 1;
    }
}

fn cellRuns(cell: ?lc.Value) []const lc.StyleRun {
    const v = cell orelse return &.{};
    return switch (v) {
        .general => |g| g.runs,
        .time => |t| t.runs,
        else => &.{},
    };
}

fn mergeStyle(base: vaxis.Style, runs: []const lc.StyleRun, byte: usize) vaxis.Style {
    var out = base;
    for (runs) |run| {
        if (byte >= run.start and byte < run.start + run.len) {
            if (run.style.bold) out.bold = true;
            if (run.style.underline) out.ul_style = .single;
            if (run.style.italic) out.italic = true;
        }
    }
    return out;
}

/// Renders a cell to display text. Stable variants (general/time) reference the
/// file's arena directly; formatted variants (numeric/date/boolean) are written
/// into `fa`, which must outlive the frame.
fn cellDisplay(fa: std.mem.Allocator, cell: ?lc.Value) ![]const u8 {
    const v = cell orelse return "";
    return switch (v) {
        .general => |g| g.text,
        .time => |t| t.text,
        .boolean => |b| if (b) "Y" else "N",
        .numeric => |n| try std.fmt.allocPrint(fa, "{d}", .{n}),
        .date => |d| try std.fmt.allocPrint(fa, "{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day }),
    };
}

// ── status line ──────────────────────────────────────────────────────────────

fn drawStatus(win: vaxis.Window, st: *const AppState, fa: std.mem.Allocator) void {
    const y = win.height - 1;
    const total = st.file.records.len;
    const n = if (total == 0) 0 else st.cursor_row + 1;
    const msg = st.status();
    const line = std.fmt.allocPrint(fa, "{s}  \u{2502}  record {d}/{d}  \u{2502}  {s}", .{
        baseName(st.path),
        n,
        total,
        if (msg.len > 0) msg else "j/k move  g/G ends  PgUp/PgDn page  h/l scroll  e export  q quit",
    }) catch return;
    putTrunc(win, 0, y, line, win.width, .{ .reverse = true });
    // Pad the rest of the status row so the reverse-video bar spans the width.
    var x: u16 = @intCast(@min(displayWidth(line), win.width));
    while (x < win.width) : (x += 1) putCell(win, x, y, " ", .{ .reverse = true });
}

pub fn baseName(path: []const u8) []const u8 {
    var name = path;
    if (std.mem.lastIndexOfScalar(u8, name, '/')) |i| name = name[i + 1 ..];
    return name;
}

// ── low-level cell painting ──────────────────────────────────────────────────

/// Writes a UTF-8 string starting at (x, y), one codepoint per cell. Callers
/// must ensure `s` outlives the next `vx.render()` (see file header).
fn put(win: vaxis.Window, x: u16, y: u16, s: []const u8, style: vaxis.Style) void {
    putTrunc(win, x, y, s, std.math.maxInt(usize), style);
}

fn putTrunc(win: vaxis.Window, x: u16, y: u16, s: []const u8, maxw: usize, style: vaxis.Style) void {
    if (y >= win.height) return;
    var col: u16 = x;
    var it = std.unicode.Utf8Iterator{ .bytes = s, .i = 0 };
    var painted: usize = 0;
    while (it.i < s.len and painted < maxw) : (painted += 1) {
        const start = it.i;
        _ = it.nextCodepoint() orelse break;
        if (col >= win.width) break;
        putCell(win, col, y, s[start..it.i], style);
        col += 1;
    }
}

fn putCell(win: vaxis.Window, x: u16, y: u16, grapheme: []const u8, style: vaxis.Style) void {
    if (x >= win.width or y >= win.height) return;
    win.writeCell(x, y, .{
        .char = .{ .grapheme = grapheme, .width = 1 },
        .style = style,
    });
}

/// Codepoint count — the display width for our single-width glyph set.
fn displayWidth(s: []const u8) usize {
    var n: usize = 0;
    var it = std.unicode.Utf8Iterator{ .bytes = s, .i = 0 };
    while (it.nextCodepoint()) |_| n += 1;
    return n;
}

test "baseName strips directory" {
    try std.testing.expectEqualStrings("TESTDB.FOL", baseName("test/TESTDB.FOL"));
    try std.testing.expectEqualStrings("x.FOL", baseName("x.FOL"));
}
