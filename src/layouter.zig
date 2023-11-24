const std = @import("std");
const font = @import("font.zig");
const unicode = @import("std").unicode;

/// Internaly everything is in units; functions/methods return values in points.
pub const Layouter = struct {
    text: []const u8 = undefined,
    utf8Iter: unicode.Utf8Iterator = undefined,
    pos: usize = undefined,
    width: usize = undefined,
    fontSize: u16 = 12,
    font: font.Font,

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
    pub fn init(text: []const u8, columnWidth: u32, fontSize: u16, fontId: u16) !Layouter {
        const usedFont = font.predefinedFonts[fontId - 1];
        var layouter = Layouter{ .pos = 0, .text = text, .width = columnWidth * usedFont.unitsPerEm, .fontSize = fontSize, .font = usedFont };
        layouter.utf8Iter = (try unicode.Utf8View.init(text)).iterator();
        return layouter;
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
            currentWidth += self.font.glyphAdvances.*[char] * self.fontSize;
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
            currentWidth += self.font.glyphAdvances.*[char] * self.fontSize;

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
    var parser = try Layouter.init("my_extremely_long_file_name.zip", 72, 12, font.PredefinedFonts.helveticaRegular);
    try std.testing.expectEqualSlices(u8, "my_", parser.nextLine() orelse ""); // Todo: use .? but this crashes zig 0.11.0
}

test "chop overflowing word" {
    var parser = try Layouter.init("abcdefghijklmnopqrstuvwxyz", 72, 12, font.PredefinedFonts.helveticaRegular);
    try std.testing.expectEqualSlices(u8, "abcdefghijkl", parser.nextLine() orelse ""); // Todo: use .? but this crashes zig 0.11.0
}

test "split text into rows" {
    var parser = try Layouter.init("a a a a a a a a a a a a a a a a a a a a a", 72, 12, font.PredefinedFonts.helveticaRegular);
    try std.testing.expectEqualSlices(u8, "a a a a a a a ", parser.nextLine() orelse "");
    try std.testing.expectEqualSlices(u8, "a a a a a a a ", parser.nextLine() orelse "");
    try std.testing.expectEqualSlices(u8, "a a a a a a a", parser.nextLine() orelse "");
    try std.testing.expectEqual(@as(?[]const u8, null), parser.nextLine());
}

test "handle umlaut" {
    var parser = try Layouter.init("ä ö ü", 72, 12, font.PredefinedFonts.helveticaRegular);
    try std.testing.expectEqualSlices(u8, "ä ö ü", parser.nextLine() orelse "");
}
