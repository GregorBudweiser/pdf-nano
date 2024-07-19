const std = @import("std");
const font = @import("font.zig");
const unicode = @import("std").unicode;
const PageProperties = @import("page_properties.zig").PageProperties;
const PDFWriter = @import("writer.zig").PDFWriter;

pub const TextAlignment = enum(c_uint) { LEFT, CENTERED, RIGHT };

/// Internaly everything is in units; functions/methods return values in points.
pub const Layouter = struct {
    text: []const u8 = undefined,
    utf8Iter: unicode.Utf8Iterator = undefined,
    pos: usize = undefined,
    x: u16,
    /// in font specific unit (unit per em)
    width: usize = undefined,
    fontSize: u16 = 12,
    font: font.Font,
    alignment: TextAlignment,

    const Limiter = enum {
        whitespace,
        linefeed,
        overflow, // single word overflows width
        endOfString,
    };

    const Word = struct {
        length: usize = undefined,
        width: usize = undefined,
        limiter: Limiter = undefined,
    };

    /// @param: columnWidth in points (1/72th inch)
    pub fn init(text: []const u8, columnStart: u16, columnWidth: u16, fontSize: u16, fontId: u16, alignment: TextAlignment) !Layouter {
        const usedFont = font.predefinedFonts[fontId - 1];
        var layouter = Layouter{
            .pos = 0,
            .text = text,
            .x = columnStart,
            .width = columnWidth * usedFont.unitsPerEm,
            .fontSize = fontSize,
            .font = usedFont,
            .alignment = alignment,
        };
        layouter.utf8Iter = (try unicode.Utf8View.init(text)).iterator();
        return layouter;
    }

    pub fn layoutLine(self: *Layouter, line: []const u8, y: i32, writer: *PDFWriter) !void {
        switch (self.alignment) {
            .RIGHT => {
                const x = @as(usize, @intCast(self.x)) + self.width / self.font.unitsPerEm - try self.getLineLength(line) / self.font.unitsPerEm;
                try writer.putText(line, self.font.id, self.fontSize, @intCast(x), y);
            },
            .CENTERED => {
                const x = @as(usize, @intCast(self.x)) + (self.width / self.font.unitsPerEm - try self.getLineLength(line) / self.font.unitsPerEm) / 2;
                try writer.putText(line, self.font.id, self.fontSize, @intCast(x), y);
            },
            // default is left aligned
            else => {
                try writer.putText(line, self.font.id, self.fontSize, self.x, y);
            },
        }
    }

    /// length of the line in current font's units per em
    /// ignores whitespace characters at the end of the line/string
    /// by design no whitespace should be at the beginning of the line/string
    fn getLineLength(self: *const Layouter, line: []const u8) !usize {
        var currentWidth: usize = 0;
        var whiteSpaceAtEnd: usize = 0;
        var iter = (try unicode.Utf8View.init(line)).iterator();
        while (iter.nextCodepoint()) |char| {
            currentWidth += self.font.glyphAdvances[char] * self.fontSize;
            if (char < 0x100 and std.ascii.isWhitespace(@intCast(char))) {
                whiteSpaceAtEnd += self.font.glyphAdvances[char] * self.fontSize;
            } else {
                whiteSpaceAtEnd = 0;
            }
        }
        return currentWidth - whiteSpaceAtEnd;
    }

    pub fn getLineHeight(self: *const Layouter) u16 {
        return self.font.getLineHeight(self.fontSize);
    }

    // baseline to highest point
    pub fn getBaseline(self: *const Layouter) u16 {
        return self.font.getBaseline(self.fontSize);
    }

    pub fn getLineGap(self: *const Layouter) u16 {
        return self.font.getLineGap(self.fontSize);
    }

    pub fn remainingText(self: *Layouter) []const u8 {
        return self.text[self.pos..];
    }

    /// Get the longest sequence of words that still fits into the given column width
    /// If the first word is too large to fit, cut it (if possible at special chars such as dash, underscore etc.)
    pub fn nextLine(self: *Layouter) ?[]const u8 {
        if (self.pos >= self.text.len) {
            return null;
        }

        const max = self.width;
        var currentPos = self.pos;
        var currentWidth: usize = 0;
        while (self.nextWord(currentPos, currentWidth)) |word| {
            if (currentWidth + word.width > max and word.limiter != Limiter.whitespace) {
                break;
            }

            currentPos += word.length;
            currentWidth += word.width;
            if (word.limiter == Limiter.linefeed) {
                break;
            }
        }

        // handle if no progress was made (word does not fit line)
        if (currentPos == self.pos) {
            return self.nextWordChopped(currentPos);
        }

        const lastPos = self.pos;
        self.pos = currentPos;
        return self.text[lastPos..@min(currentPos, self.text.len)];
    }

    fn nextWord(self: *Layouter, pos: usize, prevWidth: usize) ?Word {
        if (pos >= self.text.len or prevWidth > self.width) {
            return null;
        }
        const spaceLeft = self.width - prevWidth;
        var currentWidth: usize = 0;
        var word: Word = Word{ .limiter = Limiter.endOfString };
        self.utf8Iter.i = pos;

        while (self.utf8Iter.nextCodepoint()) |char| {
            if (char < self.font.glyphAdvances.len) {
                currentWidth += self.font.glyphAdvances[char] * self.fontSize;
            } else {
                currentWidth += self.font.max * self.fontSize;
            }
            if (char == std.ascii.control_code.lf) {
                word.limiter = Limiter.linefeed;
                break;
            } else if (char < 0x100 and std.ascii.isWhitespace(@intCast(char))) {
                word.limiter = Limiter.whitespace;
                break;
            } else if (currentWidth > spaceLeft) {
                word.limiter = Limiter.overflow;
                break;
            }
        }

        word.length = self.utf8Iter.i - pos;
        word.width = currentWidth;
        return word;
    }

    fn nextWordChopped(self: *Layouter, pos: usize) []const u8 {
        var currentWidth: usize = 0;
        self.utf8Iter.i = pos;

        var split: usize = 0;
        var lastPos: usize = pos; // position before current character/codepoint
        while (self.utf8Iter.nextCodepoint()) |char| {
            currentWidth += self.font.glyphAdvances[char] * self.fontSize;

            // natural split point
            if (char == '_' or char == '.' or char == '-') {
                split = self.utf8Iter.i;
            }

            if (currentWidth > self.width) {
                if (split == 0) {
                    split = lastPos;
                }
                break;
            }

            lastPos = self.utf8Iter.i;
        }

        self.pos = split;
        return self.text[pos..split];
    }
};

test "chop overflowing word at natrual breaks" {
    var parser = try Layouter.init("my_extremely_long_file_name.zip", 0, 72, 12, font.PredefinedFonts.helveticaRegular, TextAlignment.LEFT);
    try std.testing.expectEqualSlices(u8, "my_", parser.nextLine().?);
}

test "chop overflowing word" {
    var parser = try Layouter.init("abcdefghijklmnopqrstuvwxyz", 0, 72, 12, font.PredefinedFonts.helveticaRegular, TextAlignment.LEFT);
    try std.testing.expectEqualSlices(u8, "abcdefghijkl", parser.nextLine().?);
}

test "split text into rows" {
    var parser = try Layouter.init("a a a a a a a a a a a a a a a a a a a a a", 0, 72, 12, font.PredefinedFonts.helveticaRegular, TextAlignment.LEFT);
    try std.testing.expectEqualSlices(u8, "a a a a a a a ", parser.nextLine().?);
    try std.testing.expectEqualSlices(u8, "a a a a a a a ", parser.nextLine().?);
    try std.testing.expectEqualSlices(u8, "a a a a a a a", parser.nextLine().?);
    try std.testing.expectEqual(@as(?[]const u8, null), parser.nextLine());
}

test "handle umlaut" {
    var parser = try Layouter.init("ä ö ü", 0, 72, 12, font.PredefinedFonts.helveticaRegular, TextAlignment.LEFT);
    try std.testing.expectEqualSlices(u8, "ä ö ü", parser.nextLine().?);
}
