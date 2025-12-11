const std = @import("std");
const font = @import("font.zig");
const unicode = @import("std").unicode;
const PageProperties = @import("page_properties.zig").PageProperties;
const PDFWriter = @import("writer.zig").PDFWriter;
const Style = @import("document.zig").Style;
const Color = @import("writer.zig").Color;

pub const TextAlignment = enum(c_uint) { LEFT, CENTERED, RIGHT };

/// Internaly everything is in units; functions/methods return values in points.
pub const Layouter = struct {
    text: []const u8 = undefined,
    utf8_iter: unicode.Utf8Iterator = undefined,
    pos: usize = undefined,
    x: u16,
    /// in font specific unit (unit per em)
    width: usize = undefined,
    style: Style,

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
    pub fn init(text: []const u8, column_start: u16, column_width: u16, style: Style) !Layouter {
        const iter = (try unicode.Utf8View.init(text)).iterator();
        return Layouter{
            .pos = 0,
            .text = text,
            .x = column_start,
            .width = column_width * style.font.units_per_em,
            .style = style,
            .utf8_iter = iter,
        };
    }

    pub fn layoutLine(self: *Layouter, line: []const u8, y: i32, writer: *PDFWriter) !void {
        switch (self.style.alignment) {
            .RIGHT => {
                const x = @as(usize, @intCast(self.x)) + self.width / self.style.font.units_per_em - try self.getLineLength(line) / self.style.font.units_per_em;
                try writer.putText(line, self.style.font.id, self.style.font_size, @intCast(x), y);
            },
            .CENTERED => {
                const x = @as(usize, @intCast(self.x)) + (self.width / self.style.font.units_per_em - try self.getLineLength(line) / self.style.font.units_per_em) / 2;
                try writer.putText(line, self.style.font.id, self.style.font_size, @intCast(x), y);
            },
            // default is left aligned
            else => {
                try writer.putText(line, self.style.font.id, self.style.font_size, self.x, y);
            },
        }
    }

    /// length of the line in current font's units per em
    /// ignores whitespace characters at the end of the line/string
    /// by design no whitespace should be at the beginning of the line/string
    fn getLineLength(self: *const Layouter, line: []const u8) !usize {
        var current_width: usize = 0;
        var trailing_whitespace: usize = 0;
        var iter = (try unicode.Utf8View.init(line)).iterator();
        while (iter.nextCodepoint()) |char| {
            current_width += charWidth(char, self.style);
            if (char < 0x100 and std.ascii.isWhitespace(@intCast(char))) {
                trailing_whitespace += charWidth(char, self.style);
            } else {
                trailing_whitespace = 0;
            }
        }
        return current_width - trailing_whitespace;
    }

    pub fn getLineHeight(self: *const Layouter) u16 {
        return self.style.font.getLineHeight(self.style.font_size);
    }

    // baseline to highest point
    pub fn getBaseline(self: *const Layouter) u16 {
        return self.style.font.getBaseline(self.style.font_size);
    }

    pub fn getLineGap(self: *const Layouter) u16 {
        return self.style.font.getLineGap(self.style.font_size);
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
        var current_pos = self.pos;
        var current_width: usize = 0;
        while (self.nextWord(current_pos, current_width)) |word| {
            if (current_width + word.width > max and word.limiter != Limiter.whitespace) {
                break;
            }

            current_pos += word.length;
            current_width += word.width;
            if (word.limiter == Limiter.linefeed) {
                break;
            }
        }

        // handle if no progress was made (word does not fit line)
        if (current_pos == self.pos) {
            return self.nextWordChopped(current_pos);
        }

        const last_pos = self.pos;
        self.pos = current_pos;
        return self.text[last_pos..@min(current_pos, self.text.len)];
    }

    fn nextWord(self: *Layouter, pos: usize, prev_width: usize) ?Word {
        if (pos >= self.text.len or prev_width > self.width) {
            return null;
        }
        const space_left = self.width - prev_width;
        var current_width: usize = 0;
        var word: Word = Word{ .limiter = Limiter.endOfString };
        self.utf8_iter.i = pos;

        while (self.utf8_iter.nextCodepoint()) |char| {
            current_width += charWidth(char, self.style);
            if (char == std.ascii.control_code.lf) {
                word.limiter = Limiter.linefeed;
                break;
            } else if (char < 0x100 and std.ascii.isWhitespace(@intCast(char))) {
                word.limiter = Limiter.whitespace;
                break;
            } else if (current_width > space_left) {
                word.limiter = Limiter.overflow;
                break;
            }
        }

        word.length = self.utf8_iter.i - pos;
        word.width = current_width;
        return word;
    }

    fn nextWordChopped(self: *Layouter, pos: usize) []const u8 {
        var current_width: usize = 0;
        self.utf8_iter.i = pos;

        var split: usize = 0;
        var last_pos: usize = pos; // position before current character/codepoint
        while (self.utf8_iter.nextCodepoint()) |char| {
            current_width += charWidth(char, self.style);

            // natural split point
            if (char == '_' or char == '.' or char == '-') {
                split = self.utf8_iter.i;
            }

            if (current_width > self.width) {
                if (split == 0) {
                    split = last_pos;
                }
                break;
            }

            last_pos = self.utf8_iter.i;
        }

        self.pos = split;
        return self.text[pos..split];
    }

    fn charWidth(char: u21, style: Style) u16 {
        if (char < style.font.glyph_advances.len) {
            return style.font.glyph_advances[char] * style.font_size;
        } else {
            return style.font.max * style.font_size;
        }
    }
};

fn getTestStyle() Style {
    return Style{
        .font = font.PredefinedFonts.helvetica_regular,
        .font_size = 12,
        .font_color = Color.BLACK,
        .stroke_color = Color.BLACK,
        .fill_color = Color.WHITE,
        .alignment = TextAlignment.LEFT,
    };
}

test "chop overflowing word at natrual breaks" {
    var parser = try Layouter.init("my_extremely_long_file_name.zip", 0, 72, getTestStyle());
    try std.testing.expectEqualSlices(u8, "my_", parser.nextLine().?);
}

test "chop overflowing word" {
    var parser = try Layouter.init("abcdefghijklmnopqrstuvwxyz", 0, 72, getTestStyle());
    try std.testing.expectEqualSlices(u8, "abcdefghijkl", parser.nextLine().?);
}

test "split text into rows" {
    var parser = try Layouter.init("a a a a a a a a a a a a a a a a a a a a a", 0, 72, getTestStyle());
    try std.testing.expectEqualSlices(u8, "a a a a a a a ", parser.nextLine().?);
    try std.testing.expectEqualSlices(u8, "a a a a a a a ", parser.nextLine().?);
    try std.testing.expectEqualSlices(u8, "a a a a a a a", parser.nextLine().?);
    try std.testing.expectEqual(@as(?[]const u8, null), parser.nextLine());
}

test "handle umlaut" {
    var parser = try Layouter.init("ä ö ü", 0, 72, getTestStyle());
    try std.testing.expectEqualSlices(u8, "ä ö ü", parser.nextLine().?);
}

test "handle non-latin chars" {
    var parser = try Layouter.init("• Test", 0, 72, getTestStyle());
    try std.testing.expectEqualSlices(u8, "• Test", parser.nextLine().?);
    try std.testing.expectEqual(79572, try parser.getLineLength("• Test"));
}
