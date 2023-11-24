const std = @import("std");
const testing = std.testing;

const N: usize = 1024 * 1024;

const OffsetSubtable = struct {
    scalerType: [4]u8 = undefined,
    numTables: u16 = undefined,
    searchRange: u16 = undefined,
    entrySelector: u16 = undefined,
    rangeShift: u16,

    pub fn parse(self: *OffsetSubtable, data: []const u8) usize {
        self.scalerType = data[0..4].*;
        self.numTables = std.mem.readIntBig(u16, data[4..6]);
        self.searchRange = std.mem.readIntBig(u16, data[6..8]);
        self.entrySelector = std.mem.readIntBig(u16, data[8..10]);
        self.rangeShift = std.mem.readIntBig(u16, data[10..12]);
        return 12;
    }
};

const TableDirectory = struct {
    tag: [4]u8 = undefined,
    checkSum: u32,
    offset: u32,
    length: u32,

    pub fn parse(self: *TableDirectory, data: []const u8) usize {
        self.tag = data[0..4].*;
        self.checkSum = std.mem.readIntBig(u32, data[4..8]);
        self.offset = std.mem.readIntBig(u32, data[8..12]);
        self.length = std.mem.readIntBig(u32, data[12..16]);
        return 16;
    }
};

const HEAD = struct {
    unitsPerEm: u16 = undefined,

    pub fn parse(self: *HEAD, data: []const u8) usize {
        self.unitsPerEm = std.mem.readIntBig(u16, data[18..20]);
        return 16;
    }
};

const HHEA = struct {
    ascent: i16, // "FWord" i.e. to be divided by unitsPerEm?
    descent: i16,
    lineGap: i16,
    numOfLongHorMetrics: u16,

    pub fn parse(self: *HHEA, data: []const u8) usize {
        self.ascent = std.mem.readIntBig(i16, data[4..6]);
        self.descent = std.mem.readIntBig(i16, data[6..8]);
        self.lineGap = std.mem.readIntBig(i16, data[8..10]);
        self.numOfLongHorMetrics = std.mem.readIntBig(u16, data[34..36]);
        return 4;
    }
};

const LongHorMetrics = struct {
    advanceWidth: u16,
    leftSideBearing: i16,
};

const HMTX = struct {
    hMetrics: [0xFFFF]LongHorMetrics = undefined,

    pub fn parse(self: *HMTX, data: []const u8, count: u16) void {
        var i: u16 = 0;
        var pos: usize = 0;
        while (i < count) : (i += 1) {
            self.hMetrics[i].advanceWidth = std.mem.readIntBig(u16, data[pos..][0..2]);
            self.hMetrics[i].leftSideBearing = std.mem.readIntBig(i16, data[pos..][2..4]);
            pos += 4;
        }

        var char: u8 = 32;
        while (char < 126) : (char += 1) {
            //std.log.debug("{s}: {d}, {d}\n", .{ [_]u8{char}, self.hMetrics[char - 29].advanceWidth, self.hMetrics[char - 29].leftSideBearing });
        }
    }
};

const CMAPIndex = struct {
    version: u16,
    numSubtables: u16,

    pub fn parse(self: *CMAPIndex, data: []const u8) usize {
        self.version = std.mem.readIntBig(u16, data[0..2]);
        self.numSubtables = std.mem.readIntBig(u16, data[2..4]);
        return 4;
    }
};

const CMAPSubtable = struct {
    platformId: u16,
    platformSpecificId: u16,
    offset: u32,

    pub fn parse(self: *CMAPSubtable, data: []const u8) usize {
        self.platformId = std.mem.readIntBig(u16, data[0..2]);
        self.platformSpecificId = std.mem.readIntBig(u16, data[2..4]);
        self.offset = std.mem.readIntBig(u32, data[4..8]);
        return 8;
    }
};

const CMAPFormat = struct {
    format: u16,
    length: u16,
    language: u16,

    // format4
    segCount: u16,
    searchRange: u16,
    entrySelector: u16,
    rangeShift: u16,
    mapping: [0xFFFF]u16 = [_]u16{0x0} ** 0xFFFF,

    pub fn parse(self: *CMAPFormat, data: []const u8) void {
        self.format = std.mem.readIntBig(u16, data[0..2]);
        self.length = std.mem.readIntBig(u16, data[2..4]);
        self.language = std.mem.readIntBig(u16, data[4..6]);
        std.log.debug("CMAP fmt: format={d}, length={d}\n", .{ self.format, self.length });
        if (self.format == 4) {
            self.segCount = std.mem.readIntBig(u16, data[6..8]) / 2;
            self.searchRange = std.mem.readIntBig(u16, data[8..10]);
            self.entrySelector = std.mem.readIntBig(u16, data[10..12]);
            self.rangeShift = std.mem.readIntBig(u16, data[12..14]);
            std.log.debug("CMAP fmt segCount: {d}, searchRange: {d}, entrySelector: {d}, rangeshift: {d}\n", .{ self.segCount, self.searchRange, self.entrySelector, self.rangeShift });
            var i: u16 = 0;
            while (i < self.segCount) : (i += 1) {
                const endCode = 14 + i * 2;
                const startCode = endCode + 2 * self.segCount + 2;
                const idDelta = startCode + 2 * self.segCount;
                const idRangeOffset = idDelta + 2 * self.segCount;
                //const glyphIndexArray = idRangeOffset + 2 * self.segCount;

                const start = std.mem.readIntBig(u16, data[startCode..][0..2]);
                const end = std.mem.readIntBig(u16, data[endCode..][0..2]);
                const delta = std.mem.readIntBig(u16, data[idDelta..][0..2]);
                const range = std.mem.readIntBig(u16, data[idRangeOffset..][0..2]);

                //std.log.debug("Segment: [{d},{d}], {d}, {d}\n", .{ start, end, delta, range });

                var charCode = start;
                while (charCode < end) : (charCode += 1) {
                    var glyphIndex: u16 = 0;
                    if (range == 0) {
                        glyphIndex = charCode +% delta;
                    } else {
                        glyphIndex = std.mem.readIntBig(u16, data[idRangeOffset + range + 2 * (charCode - start) ..][0..2]);
                    }
                    self.mapping[charCode] = glyphIndex;
                }
            }
        }
    }
};

const CMAP = struct {
    index: CMAPIndex = undefined,

    pub fn parse(self: *CMAP, data: []const u8) ?CMAPFormat {
        var pos = self.index.parse(data);

        //std.log.debug("Index: {any}\n", .{self.index});

        var i: u16 = 0;
        while (i < self.index.numSubtables) : (i += 1) {
            var sub: CMAPSubtable = undefined;
            pos += sub.parse(data[pos..]);
            std.log.debug("CMAP sub: {any}\n", .{sub});

            // unicode
            if (sub.platformId == 0) {
                var format: CMAPFormat = undefined;
                format.parse(data[sub.offset..]);
                return format;
            }
        }
        return null;
    }
};

const TTFParser = struct {
    buffer: [N]u8 = undefined,
    size: usize = undefined,
    pos: usize = undefined,
    subtable: OffsetSubtable = undefined,
    tableDir: TableDirectory = undefined,

    pub fn init(filename: []const u8) !TTFParser {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        var parser = TTFParser{ .pos = 0 };
        parser.size = try file.readAll(&parser.buffer);
        std.log.debug("Size: {d}KB\n", .{parser.size / 1024});
        return parser;
    }

    pub fn parse(self: *TTFParser) void {
        self.pos = self.subtable.parse(self.buffer[0..]);
        std.log.debug("Subtable: {any}\n", .{self.subtable});

        var head: HEAD = undefined;
        var cmap: CMAP = undefined;
        var hhea: HHEA = undefined;
        var hmtx: HMTX = undefined;
        var cmapFormat: CMAPFormat = undefined;

        var i: u16 = 0;

        while (i < self.subtable.numTables) : (i += 1) {
            self.pos += self.tableDir.parse(self.buffer[self.pos..]);
            if (std.mem.eql(u8, &self.tableDir.tag, "cmap")) {
                var start = self.tableDir.offset;
                var end = start + self.tableDir.length;
                if (cmap.parse(self.buffer[start..end])) |fmt| {
                    cmapFormat = fmt;
                }

                std.log.debug("Dir entry: {any}\n", .{self.tableDir});
                std.log.debug("HHEA: {any}\n", .{hhea});
                break;
            }
        }

        while (i < self.subtable.numTables) : (i += 1) {
            self.pos += self.tableDir.parse(self.buffer[self.pos..]);
            if (std.mem.eql(u8, &self.tableDir.tag, "head")) {
                std.log.debug("Dir entry: {any}\n", .{self.tableDir});
                var start = self.tableDir.offset;
                var end = start + self.tableDir.length;
                _ = head.parse(self.buffer[start..end]);
                std.log.debug("head: {any}\n", .{head});
                break;
            }
        }

        while (i < self.subtable.numTables) : (i += 1) {
            self.pos += self.tableDir.parse(self.buffer[self.pos..]);
            if (std.mem.eql(u8, &self.tableDir.tag, "hhea")) {
                var start = self.tableDir.offset;
                var end = start + self.tableDir.length;
                _ = hhea.parse(self.buffer[start..end]);

                std.log.debug("Dir entry: {any}\n", .{self.tableDir});
                std.log.debug("HHEA: {any}\n", .{hhea});
                break;
            }
        }

        while (i < self.subtable.numTables) : (i += 1) {
            self.pos += self.tableDir.parse(self.buffer[self.pos..]);
            if (std.mem.eql(u8, &self.tableDir.tag, "hmtx")) {
                std.log.debug("HMTX: {any}\n", .{self.tableDir});
                var start = self.tableDir.offset;
                var end = start + self.tableDir.length;
                hmtx.parse(self.buffer[start..end], hhea.numOfLongHorMetrics);
            }
        }

        std.log.debug("a : {any}\n", .{hmtx.hMetrics[cmapFormat.mapping["a"[0]]]});
        std.log.debug("ae: {any}\n", .{hmtx.hMetrics[cmapFormat.mapping[0xe4]]});
        std.log.debug("o : {any}\n", .{hmtx.hMetrics[cmapFormat.mapping["o"[0]]]});
        std.log.debug("oe: {any}\n", .{hmtx.hMetrics[cmapFormat.mapping[0xf6]]});
        std.log.debug("u : {any}\n", .{hmtx.hMetrics[cmapFormat.mapping["u"[0]]]});
        std.log.debug("ue: {any}\n", .{hmtx.hMetrics[cmapFormat.mapping[0xfc]]});

        var latin1: [0x100]u16 = undefined;
        var char: u16 = 0;
        while (char < latin1.len) : (char += 1) {
            latin1[char] = hmtx.hMetrics[cmapFormat.mapping[char]].advanceWidth;
        }
        std.log.debug("{any}\n", .{latin1[0..].*});
    }
};

test "init deinit" {
    std.testing.log_level = .debug;
    var parser = try TTFParser.init("res/helvetica.ttf");
    parser.parse();
    try testing.expect(0 == 0);
}

const unicode = @import("std").unicode;
test "unicode stuff" {
    const name = "äöü";
    var code_point_iterator = (try unicode.Utf8View.init(name)).iterator();
    while (code_point_iterator.nextCodepoint()) |code_point| {
        std.debug.print("0x{x}\n", .{code_point});
    }
}
