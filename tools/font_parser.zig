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
        self.numTables = std.mem.readInt(u16, data[4..6], std.builtin.Endian.big);
        self.searchRange = std.mem.readInt(u16, data[6..8], std.builtin.Endian.big);
        self.entrySelector = std.mem.readInt(u16, data[8..10], std.builtin.Endian.big);
        self.rangeShift = std.mem.readInt(u16, data[10..12], std.builtin.Endian.big);
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
        self.checkSum = std.mem.readInt(u32, data[4..8], std.builtin.Endian.big);
        self.offset = std.mem.readInt(u32, data[8..12], std.builtin.Endian.big);
        self.length = std.mem.readInt(u32, data[12..16], std.builtin.Endian.big);
        return 16;
    }
};

const HEAD = struct {
    unitsPerEm: u16 = undefined,

    pub fn parse(self: *HEAD, data: []const u8) usize {
        self.unitsPerEm = std.mem.readInt(u16, data[18..20], std.builtin.Endian.big);
        return 16;
    }
};

const HHEA = struct {
    ascent: i16, // "FWord" i.e. to be divided by unitsPerEm?
    descent: i16,
    lineGap: i16,
    numOfLongHorMetrics: u16,

    pub fn parse(self: *HHEA, data: []const u8) usize {
        self.ascent = std.mem.readInt(i16, data[4..6], std.builtin.Endian.big);
        self.descent = std.mem.readInt(i16, data[6..8], std.builtin.Endian.big);
        self.lineGap = std.mem.readInt(i16, data[8..10], std.builtin.Endian.big);
        self.numOfLongHorMetrics = std.mem.readInt(u16, data[34..36], std.builtin.Endian.big);
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
            self.hMetrics[i].advanceWidth = std.mem.readInt(u16, data[pos..][0..2], std.builtin.Endian.big);
            self.hMetrics[i].leftSideBearing = std.mem.readInt(i16, data[pos..][2..4], std.builtin.Endian.big);
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
        self.version = std.mem.readInt(u16, data[0..2], std.builtin.Endian.big);
        self.numSubtables = std.mem.readInt(u16, data[2..4], std.builtin.Endian.big);
        return 4;
    }
};

const CMAPSubtable = struct {
    platformId: u16,
    platformSpecificId: u16,
    offset: u32,

    pub fn parse(self: *CMAPSubtable, data: []const u8) usize {
        self.platformId = std.mem.readInt(u16, data[0..2], std.builtin.Endian.big);
        self.platformSpecificId = std.mem.readInt(u16, data[2..4], std.builtin.Endian.big);
        self.offset = std.mem.readInt(u32, data[4..8], std.builtin.Endian.big);
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
    mapping: [0x10000]u16 = [_]u16{0x0} ** 0x10000,

    pub fn parse(self: *CMAPFormat, data: []const u8) void {
        self.format = std.mem.readInt(u16, data[0..2], std.builtin.Endian.big);
        self.length = std.mem.readInt(u16, data[2..4], std.builtin.Endian.big);
        self.language = std.mem.readInt(u16, data[4..6], std.builtin.Endian.big);
        std.log.debug("CMAP fmt: format={d}, length={d}", .{ self.format, self.length });
        if (self.format == 4) {
            self.segCount = std.mem.readInt(u16, data[6..8], std.builtin.Endian.big) / 2;
            self.searchRange = std.mem.readInt(u16, data[8..10], std.builtin.Endian.big);
            self.entrySelector = std.mem.readInt(u16, data[10..12], std.builtin.Endian.big);
            self.rangeShift = std.mem.readInt(u16, data[12..14], std.builtin.Endian.big);
            std.log.debug("CMAP fmt segCount: {d}, searchRange: {d}, entrySelector: {d}, rangeshift: {d}", .{ self.segCount, self.searchRange, self.entrySelector, self.rangeShift });
            var i: u16 = 0;
            while (i < self.segCount) : (i += 1) {
                const endCode = 14 + i * 2;
                const startCode = endCode + 2 * self.segCount + 2;
                const idDelta = startCode + 2 * self.segCount;
                const idRangeOffset = idDelta + 2 * self.segCount;
                //const glyphIndexArray = idRangeOffset + 2 * self.segCount;

                const start = std.mem.readInt(u16, data[startCode..][0..2], std.builtin.Endian.big);
                const end = std.mem.readInt(u16, data[endCode..][0..2], std.builtin.Endian.big);
                const delta = std.mem.readInt(u16, data[idDelta..][0..2], std.builtin.Endian.big);
                const range = std.mem.readInt(u16, data[idRangeOffset..][0..2], std.builtin.Endian.big);

                std.log.debug("Segment: [{d},{d}], {d}, {d}", .{ start, end, delta, range });

                var charCode = start;
                while (charCode <= end and charCode != 0xFFFF) : (charCode += 1) {
                    var glyphIndex: u16 = 0;
                    if (range == 0) {
                        glyphIndex = charCode +% delta;
                    } else {
                        glyphIndex = std.mem.readInt(u16, data[idRangeOffset + range + 2 * (charCode - start) ..][0..2], std.builtin.Endian.big);
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
            std.log.debug("CMAP sub: {any}", .{sub});

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
                const start = self.tableDir.offset;
                const end = start + self.tableDir.length;
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
                const start = self.tableDir.offset;
                const end = start + self.tableDir.length;
                _ = head.parse(self.buffer[start..end]);
                std.log.debug("head: {any}\n", .{head});
                break;
            }
        }

        while (i < self.subtable.numTables) : (i += 1) {
            self.pos += self.tableDir.parse(self.buffer[self.pos..]);
            if (std.mem.eql(u8, &self.tableDir.tag, "hhea")) {
                const start = self.tableDir.offset;
                const end = start + self.tableDir.length;
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
                const start = self.tableDir.offset;
                const end = start + self.tableDir.length;
                hmtx.parse(self.buffer[start..end], hhea.numOfLongHorMetrics);
            }
        }

        std.log.debug("a : {any}\n", .{hmtx.hMetrics[cmapFormat.mapping["a"[0]]]});
        std.log.debug("ae: {any}\n", .{hmtx.hMetrics[cmapFormat.mapping[0xe4]]});
        std.log.debug("o : {any}\n", .{hmtx.hMetrics[cmapFormat.mapping["o"[0]]]});
        std.log.debug("oe: {any}\n", .{hmtx.hMetrics[cmapFormat.mapping[0xf6]]});
        std.log.debug("u : {any}\n", .{hmtx.hMetrics[cmapFormat.mapping["u"[0]]]});
        std.log.debug("ue: {any}\n", .{hmtx.hMetrics[cmapFormat.mapping[0xfc]]});
        std.log.debug("~ : {d} => {any}\n", .{ "~"[0], hmtx.hMetrics[cmapFormat.mapping["~"[0]]] });

        var latin1: [0x100]u16 = undefined;
        var char: u16 = 0;
        while (char < latin1.len) : (char += 1) {
            const glyphIndex = cmapFormat.mapping[char];
            // TODO: figure out limit..
            if (glyphIndex < 43690) {
                latin1[char] = hmtx.hMetrics[cmapFormat.mapping[char]].advanceWidth;
            } else {
                latin1[char] = 0;
            }
            std.log.debug("glyphIdx: {d} => {d}", .{ cmapFormat.mapping[char], latin1[char] });
        }
        std.log.debug("{any}\n", .{latin1[0..].*});
    }
};

test "init deinit" {
    std.testing.log_level = .debug;
    var parser = try TTFParser.init("res/helvetica-bold.ttf");
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
