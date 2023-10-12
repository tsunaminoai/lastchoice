const std = @import("std");
const Block = @import("block.zig");
const FCF = @import("fcf.zig");

pub const Header = extern struct {
    formDefinitionIndex: u16, // block# - 1
    lastUsedBlock: u16, // not accurate
    totalFileBlocks: u16, // dont count header
    dataRecords: u16,
    magicString: [14]u8,
    availableDBFields: u16,
    formLength: u16,
    formRevisions: u16, // 1 indexed
    _1: u16,
    emptiesLength: u16,
    tableViewIndex: u16,
    programRecordIndex: u16,
    _2: u16,
    _3: u16,
    nextFieldSize: u8,
    diskVar: [128 - 41]u8,

    pub fn print(self: @This()) void {
        const fmt =
            \\
            \\Form Index: {}
            \\Last Block: {}
            \\Total Blocks: {}
            \\Data Records: {}
            \\Available Fields: {}
            \\Form Length: {}
            \\Form Revisions: {}
            \\Empties Length: {}
            \\Table Index: {}
            \\Program Index: {}
            \\Next Field Size: {}
            \\@DISKVAR: "{s}"
            \\
        ;
        std.log.debug(fmt, .{
            self.formDefinitionIndex,
            self.lastUsedBlock,
            self.totalFileBlocks,
            self.dataRecords,
            self.availableDBFields,
            self.formLength,
            self.formRevisions,
            self.emptiesLength,
            self.tableViewIndex,
            self.programRecordIndex,
            self.nextFieldSize,
            self.diskVar,
        });
    }

    pub fn fromBytes(raw: *[128]u8) Header {
        var head = std.mem.bytesToValue(Header, raw);
        return head;
    }
};
