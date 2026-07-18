# LastChoice

LastChoice is a small command-line tool for recovering data from **FirstChoice
`.FOL` databases** and exporting it to modern formats: **SQLite**, CSV, and
JSON.

## What is a FOL file?

[PFS: First Choice](https://en.wikipedia.org/wiki/PFS:_First_Choice) was an
all-in-one productivity suite for DOS in the late 1980s and early 1990s. Its
flat-file database module stored data in `.FOL` files ("FirstChoice On-Line", a
`GERBILDB3`-tagged format built from 128-byte blocks). LastChoice parses that
on-disk format directly - header, form/schema, and records, including
records that span multiple blocks - and gives you the data back in a form you
can actually query today.

## Installation

Requires **Zig >= 0.16.0**. The SQLite C library is vendored and compiled
automatically through the [zig-sqlite](https://github.com/vrischmann/zig-sqlite)
dependency (SQLite amalgamation 3.48.0) - no system SQLite is needed to build.

```bash
zig build            # builds ./zig-out/bin/lastchoice
zig build run -- ... # build and run in one step
```

## Usage

```text
lastchoice info  FILE.FOL                  Print header and schema summary
lastchoice print FILE.FOL                  Print the record table to stdout
lastchoice dump  FILE.FOL [options]        Export records

Dump options:
  -o OUT       Write to OUT instead of the default/stdout
  --sqlite     Export to a SQLite database (default; OUT defaults to <name>.db)
  --csv        Export as CSV  (to stdout unless -o is given)
  --json       Export as JSON (to stdout unless -o is given)
```

`dump` defaults to SQLite. With `-o` and no explicit format flag, the format is
inferred from the output extension (`.db`/`.sqlite`/`.sqlite3` -> SQLite,
`.csv` -> CSV, `.json` -> JSON).

### Examples

```bash
# Inspect a file
lastchoice info  RESERVE.FOL
lastchoice print RESERVE.FOL

# Dump to SQLite (writes RESERVE.db by default) and query it
lastchoice dump RESERVE.FOL
sqlite3 RESERVE.db 'select * from records'

# Dump to an explicit database path
lastchoice dump RESERVE.FOL -o /tmp/reserve.db

# CSV / JSON to stdout, or to a file
lastchoice dump RESERVE.FOL --csv > reserve.csv
lastchoice dump RESERVE.FOL --json -o reserve.json
```

## SQLite output layout

A dump is a fresh single-writer database containing one main table plus two
sidecar tables:

- **`records`** - one row per record.
  `records(id INTEGER PRIMARY KEY, "<column>" <type>, ...)`. Column names come
  from the field names (blank names become `field_N`; case-insensitive
  duplicates get `_2`, `_3`, ... suffixes) and are always double-quoted. Field
  types map as follows:

  | FirstChoice kind | SQLite type | Notes                          |
  | ---------------- | ----------- | ------------------------------ |
  | Numeric          | `REAL`      |                                |
  | Bool             | `INTEGER`   | `0` / `1`                      |
  | General          | `TEXT`      |                                |
  | Date             | `TEXT`      | ISO `YYYY-MM-DD`               |
  | Time             | `TEXT`      | raw display text (see below)   |

  Blank cells are stored as `NULL`.

- **`_fields`** - `(idx INTEGER PRIMARY KEY, name TEXT, kind TEXT)`. The
  *original* field names and kinds, in schema order, preserved for fidelity even
  where the derived column names were rewritten.

- **`_formatting`** - `(record_id, field_idx, start, len, bold, underline,
  italic, background)`. One row per non-default character-formatting run,
  preserving bold/underline/etc. runs from the original text so no styling
  information is lost. `record_id` and `field_idx` are zero-based and match
  `records.id` and `_fields.idx`.

CSV and JSON use the same derived column names. JSON output is a single object
with `fields`, `records`, and `formatting` arrays; record values are typed
(numbers, booleans, ISO date strings, or `null`).

## Notes and limitations

- The exact bit layout of FirstChoice's Time field and of some character-style
  marker bytes is not fully reverse-engineered. Time values are preserved as
  their raw display text, and each style run keeps the original marker byte, so
  data is never dropped even where the interpretation is uncertain.

## Terminal browser (optional TUI)

An optional full-screen terminal browser is available behind the `-Dtui` flag.
It builds on [libvaxis](https://github.com/rockorager/libvaxis), which is a
*lazy* dependency: the default `zig build` and `zig build test` never fetch or
build it, so you only pay for it when you ask for the TUI.

```bash
zig build -Dtui tui               # builds ./zig-out/bin/lastchoice-tui
./zig-out/bin/lastchoice-tui RESERVE.FOL
```

The left pane lists the schema (field name + kind); the main pane is a
scrollable record table with the current row highlighted; the bottom line shows
the file, the current record number, and the key hints.

Keys:

| Key | Action |
| --- | --- |
| `j` / `k` or down / up | move the cursor by one record |
| `PgDn` / `PgUp` | page through records |
| `g` / `G` | jump to the first / last record |
| `h` / `l` or left / right | scroll columns horizontally |
| `e` | export to SQLite (`<basename>.db`); the result shows in the status line |
| `q` / `Ctrl-C` | quit (restores the terminal) |

The browser is a pure client of the parser library and the SQLite exporter; it
contains no parsing logic of its own.

## Development

```bash
zig build test        # run library (parser) and exporter tests
zig fmt --check .      # formatting check
```

Tests include golden parser tests over the bundled `test/TESTDB.FOL` and
`RESERVE.FOL` fixtures and end-to-end exporter tests (CSV quoting, JSON shape,
SQLite dump-and-reopen).

## Why?

While it may seem silly to have a tool to read a database that is no longer in
use, I had a few reasons for doing so. My Dad got in on using computers for
business and personal use way back in the late '80s. As a result, he had a lot
of data in FirstChoice databases. When his old machine died, he asked if I could
help recover the data in the `FOL` files he had. I knew that other converters
existed, but of these, one was a paid application, and the
[other](https://github.com/alfille/firstchoice), while an invaluable resource,
was not going to be simple enough for my dad to use.

I decided to write this tool to help him out. I also wanted to learn more about
Zig, and this seemed like a good project to do so. More than that, I realized
that there are probably more FOL files floating around in people's basements and
attics, and I wanted to make sure that there was a tool that could read them
into an extensible format for data archeology.

If this tool has been of use to you, please let me know. I'd love to hear about
it.
