//! lastchoice-tui — an optional terminal browser for FirstChoice `.FOL`
//! databases, built behind `-Dtui` (lazy vaxis dependency).
//!
//! It is a pure client: parsing is entirely in the `lc` module and export is
//! the shared `src/export/sqlite.zig`. This file owns the event loop, maps keys
//! to state changes, and calls the pure `render.draw`. Terminal plumbing shapes
//! (Tty/Vaxis/Loop) mirror the working cribbage 0.16 + vaxis 0.6.0 front end.

const std = @import("std");
const vaxis = @import("vaxis");
const lc = @import("lc");
const sqlite = @import("export_sqlite");
const render = @import("render.zig");

const AppState = render.AppState;

/// vaxis debug logs would otherwise print straight onto the browser screen.
pub const std_options: std.Options = .{ .log_level = .err };

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const usage =
    \\lastchoice-tui — browse a FirstChoice .FOL database
    \\
    \\  usage: lastchoice-tui FILE.FOL
    \\
    \\keys: j/k or up/down move   g/G top/bottom   PgUp/PgDn page
    \\      h/l or left/right scroll columns   e export SQLite   q/Ctrl-C quit
    \\
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // argv[1] = FOL path. Fail cleanly (before touching the TTY) when missing.
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer it.deinit();
    _ = it.next(); // argv0
    const path = it.next() orelse {
        std.debug.print("{s}", .{usage});
        return error.MissingPath;
    };

    var file = lc.File.init(gpa, io, path) catch |err| {
        std.debug.print("lastchoice-tui: cannot read '{s}': {s}\n", .{ path, @errorName(err) });
        return error.CannotOpenFile;
    };
    defer file.deinit();

    var state: AppState = .{ .file = file, .path = path };

    // ── terminal bootstrap (call shapes mirror cribbage) ──
    var tty_buf: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buf);
    defer tty.deinit();
    var vx = try vaxis.init(io, gpa, init.environ_map, .{});
    defer vx.deinit(gpa, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));
    const use_signal_resize = !vx.state.in_band_resize;
    if (use_signal_resize) try loop.installResizeHandler();
    defer if (use_signal_resize) loop.uninstallResizeHandler();
    try vx.resize(gpa, tty.writer(), try tty.getWinsize());

    var frame_buf: [1 << 16]u8 = undefined;
    var quit = false;
    while (!quit) {
        const win = vx.window();
        render.draw(win, &state, &frame_buf);
        try vx.render(tty.writer());

        const ev = try loop.nextEvent();
        switch (ev) {
            .winsize => |ws| try vx.resize(gpa, tty.writer(), ws),
            .key_press => |key| handleKey(key, &state, win.height, gpa, io, &quit),
        }
    }
}

fn handleKey(key: vaxis.Key, st: *AppState, win_h: u16, gpa: std.mem.Allocator, io: std.Io, quit: *bool) void {
    const visible = @as(usize, @max(win_h, 2)) - 2; // header + status rows
    const records = st.file.records.len;
    const last = records -| 1;

    if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
        quit.* = true;
    } else if (key.matches('j', .{}) or key.matches(vaxis.Key.down, .{})) {
        st.cursor_row = @min(st.cursor_row + 1, last);
    } else if (key.matches('k', .{}) or key.matches(vaxis.Key.up, .{})) {
        st.cursor_row -|= 1;
    } else if (key.matches('g', .{})) {
        st.cursor_row = 0;
    } else if (key.matches('G', .{}) or key.matches('g', .{ .shift = true })) {
        st.cursor_row = last;
    } else if (key.matches(vaxis.Key.page_down, .{})) {
        st.cursor_row = @min(st.cursor_row + visible, last);
    } else if (key.matches(vaxis.Key.page_up, .{})) {
        st.cursor_row -|= visible;
    } else if (key.matches('l', .{}) or key.matches(vaxis.Key.right, .{})) {
        const fields = st.file.schema.fields.len;
        if (fields > 0) st.col_off = @min(st.col_off + 1, fields - 1);
    } else if (key.matches('h', .{}) or key.matches(vaxis.Key.left, .{})) {
        st.col_off -|= 1;
    } else if (key.matches('e', .{})) {
        doExport(st, gpa, io);
    }

    // Keep the cursor within the visible window.
    if (st.cursor_row < st.top_row) {
        st.top_row = st.cursor_row;
    } else if (visible > 0 and st.cursor_row >= st.top_row + visible) {
        st.top_row = st.cursor_row - visible + 1;
    }
}

fn doExport(st: *AppState, gpa: std.mem.Allocator, io: std.Io) void {
    var buf: [512]u8 = undefined;
    const out = outPath(&buf, st.path);
    sqlite.write(gpa, io, st.file, out) catch |err| {
        st.setStatus("EXPORT FAILED: {s}", .{@errorName(err)});
        return;
    };
    st.setStatus("EXPORTED {s} ({d} records)", .{ out, st.file.records.len });
}

/// Derives `<basename-without-extension>.db` (in the cwd) from the input path.
fn outPath(buf: []u8, path: []const u8) []const u8 {
    var name = render.baseName(path);
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        if (dot > 0) name = name[0..dot];
    }
    return std.fmt.bufPrint(buf, "{s}.db", .{name}) catch name;
}

test {
    _ = render;
}

test "outPath strips directory and extension" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("TESTDB.db", outPath(&buf, "test/TESTDB.FOL"));
    try std.testing.expectEqualStrings("RESERVE.db", outPath(&buf, "RESERVE.FOL"));
}
