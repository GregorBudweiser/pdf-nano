const std = @import("std");
const PDFWriter = @import("writer.zig").PDFWriter;
const Color = @import("writer.zig").Color;
const Font = @import("font.zig").Font;
const PredefinedFonts = @import("font.zig").PredefinedFonts;
const Layouter = @import("layouter.zig").Layouter;
const Table = @import("table.zig").Table;

pub const PDF_NANO_VERSION: [*:0]const u8 = "0.2.0";

pub const PageOrientation = enum(c_uint) { PORTRAIT, LANDSCAPE };
pub const PageFormat = enum(c_uint) { LETTER, A4 };

/// Common page formats
const formats = [_][2]u16{
    [2]u16{ 612, 792 },
    [2]u16{ 595, 842 },
};

/// Virtual cursor inside document
const Cursor = struct {
    x: u16,
    y: u16,
    fontSize: u16,
    fontId: u16,
    fontColor: Color, // Text + Fill
    strokeColor: Color, // Lines / Strokes
    fillColor: Color, // Brackground (e.g. table cell bg)
};

/// Page properties for a single page in the document
const PageProperties = struct {
    width: u16 = 612,
    height: u16 = 792,
    documentBorder: u16 = 72 * 3 / 4, // 3/4 inch

    pub fn getContentTop(self: *const PageProperties) u16 {
        return self.height - self.documentBorder;
    }

    pub fn getContentBottom(self: *const PageProperties) u16 {
        return self.documentBorder;
    }

    pub fn getContentWidth(self: *const PageProperties) u16 {
        return self.width - 2 * self.documentBorder;
    }

    pub fn getContentLeft(self: *const PageProperties) u16 {
        return self.documentBorder;
    }

    pub fn getContentRight(self: *const PageProperties) u16 {
        return self.width - self.documentBorder;
    }
};

/// High level document struct for creating a PDF document
pub const PDFDocument = struct {
    writer: PDFWriter = undefined,
    pageProperties: PageProperties = undefined,
    cursor: Cursor = undefined,
    table: Table = undefined,
    streamPos: usize = undefined,

    pub fn init(allocator: std.mem.Allocator) PDFDocument {
        return PDFDocument{
            .writer = PDFWriter.init(allocator),
            .pageProperties = PageProperties{},
        };
    }

    pub fn deinit(self: *PDFDocument) void {
        self.writer.deinit();
    }

    /// Calling render() "finishes" the document.
    /// After that, any changes to the pdf document will not generate a valid pdf file.
    pub fn render(self: *PDFDocument) ![]const u8 {
        try self.writer.endDocument();
        return self.writer.buffer.items;
    }

    pub fn setupDocument(self: *PDFDocument, format: PageFormat, orientation: PageOrientation) !void {
        self.pageProperties.width = formats[@intFromEnum(format)][0 + @intFromEnum(orientation)];
        self.pageProperties.height = formats[@intFromEnum(format)][1 - @intFromEnum(orientation)];
        try self.writer.startDocument(self.pageProperties.width, self.pageProperties.height);
        self.resetCursor();
    }

    pub fn breakPage(self: *PDFDocument) !void {
        try self.writer.newPage(self.pageProperties.width, self.pageProperties.height);
        self.cursor.y = self.pageProperties.getContentTop();
        try self.writer.setColor(self.cursor.fontColor);
        try self.writer.setStrokeColor(self.cursor.strokeColor);
    }

    pub fn advanceCursor(self: *PDFDocument, y: u16) void {
        self.cursor.y -= y;
    }

    pub fn setFontSize(self: *PDFDocument, fontSize: u8) void {
        self.cursor.fontSize = fontSize;
    }

    pub fn setFontById(self: *PDFDocument, fontId: u8) void {
        self.cursor.fontId = fontId;
    }

    pub fn setFontColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.fontColor = Color{ .r = r, .g = g, .b = b };
    }

    pub fn setStrokeColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.strokeColor = Color{ .r = r, .g = g, .b = b };
    }

    pub fn setFillColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.fillColor = Color{ .r = r, .g = g, .b = b };
    }

    pub fn hr(self: *PDFDocument, thickness: f32) !void {
        try self.writer.setStrokeColor(self.cursor.strokeColor);
        try self.writer.putLine(thickness, self.pageProperties.getContentLeft(), self.cursor.y, self.pageProperties.getContentRight(), self.cursor.y);
    }

    pub fn addText(self: *PDFDocument, text: []const u8) !void {
        var layouter = try Layouter.init(text, self.pageProperties.getContentWidth(), self.cursor.fontSize, self.cursor.fontId);
        var y: i32 = self.cursor.y;
        while (layouter.nextLine()) |token| {
            // advance cursor by this new line, creating new page if necessary
            y -= layouter.getLineHeight();
            if (y + layouter.getLineGap() < self.pageProperties.getContentBottom()) {
                self.resetCursor();
                try self.writer.newPage(self.pageProperties.width, self.pageProperties.height);
                y = self.pageProperties.getContentTop() - layouter.getLineHeight();
            }

            try self.writer.setColor(self.cursor.fontColor);
            try self.writer.putText(token, self.cursor.fontId, layouter.fontSize, self.pageProperties.documentBorder, y + layouter.getLineHeight() - layouter.getBaseline());
        }
        self.cursor.y = @intCast(y);
    }

    pub fn writeRow(self: *PDFDocument, strings: []const []const u8) !void {
        try self.writer.setStrokeColor(self.cursor.strokeColor);
        for (self.table.getCells(), strings) |*cell, string| {
            cell.remainingText = string;
        }
        try self.table.writeRow(self);

        // handle page breaks if necessary
        while (!self.table.isRowDone()) {
            _ = try self.table.finishTable(&self.writer);
            try self.writer.newPage(self.pageProperties.width, self.pageProperties.height);
            self.table.y = self.pageProperties.getContentTop();
            self.table.currentRowY = self.table.y;

            try self.table.writeRow(self);
        }
    }

    pub fn startTable(self: *PDFDocument, columnWidths: []const u16) void {
        self.table = Table.init(columnWidths, self.pageProperties.getContentLeft(), self.cursor.y);
    }

    pub inline fn finishTable(self: *PDFDocument) !void {
        self.cursor.y = try self.table.finishTable(&self.writer);
    }

    /// Calling save() "finishes" the document by calling render().
    /// After that, any changes to the pdf document will not generate a valid pdf file.
    pub fn save(doc: *PDFDocument, filename: []const u8) !void {
        const out_file = try std.fs.cwd().createFile(filename, .{});
        defer out_file.close();
        var buf_writer = std.io.bufferedWriter(out_file.writer());
        _ = try buf_writer.write(try doc.render());
        _ = try buf_writer.flush();
    }

    fn resetCursor(self: *PDFDocument) void {
        self.cursor.x = self.pageProperties.documentBorder;
        self.cursor.y = self.pageProperties.getContentTop();
        self.cursor.fontSize = 12;
        self.cursor.fontId = PredefinedFonts.helveticaRegular;
        self.cursor.fontColor = Color{ .r = 0, .g = 0, .b = 0 };
        self.cursor.strokeColor = Color{ .r = 0, .g = 0, .b = 0 };
        self.cursor.fillColor = Color{ .r = 1, .g = 1, .b = 1 };
    }
};

test "create empty pdf" {
    std.testing.log_level = .info;
    var document = PDFDocument.init(std.heap.page_allocator);
    defer document.deinit();

    try document.setupDocument(PageFormat.A4, PageOrientation.PORTRAIT);

    var result = try document.render();
    try std.testing.expect(result.len > 0);
}

test "check enums" {
    try std.testing.expectEqual(PageFormat.LETTER, @as(PageFormat, @enumFromInt(0)));
    try std.testing.expectEqual(PageFormat.A4, @as(PageFormat, @enumFromInt(1)));

    try std.testing.expectEqual(PageOrientation.PORTRAIT, @as(PageOrientation, @enumFromInt(0)));
    try std.testing.expectEqual(PageOrientation.LANDSCAPE, @as(PageOrientation, @enumFromInt(1)));
}
