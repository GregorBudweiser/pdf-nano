const std = @import("std");
const PDFWriter = @import("writer.zig").PDFWriter;
const Font = @import("font.zig").Font;
const PredefinedFonts = @import("font.zig").PredefinedFonts;
const Layouter = @import("layouter.zig").Layouter;
const Table = @import("table.zig").Table;

pub const PDF_NANO_VERSION: [*:0]const u8 = "0.1.0";

const PageOrientation = enum(c_uint) { PORTRAIT, LANDSCAPE };
const PageFormat = enum(c_uint) { LETTER, A4 };

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

    pub fn init(allocator: std.mem.Allocator) PDFDocument {
        return PDFDocument{
            .writer = PDFWriter.init(allocator),
            .pageProperties = PageProperties{},
            .cursor = undefined,
        };
    }

    pub fn deinit(self: *PDFDocument) void {
        self.writer.deinit();
    }

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

    pub fn advanceCursor(self: *PDFDocument, y: u16) void {
        self.cursor.y -= y;
    }

    pub fn setFontSize(self: *PDFDocument, fontSize: u8) void {
        self.cursor.fontSize = fontSize;
    }

    pub fn setFontById(self: *PDFDocument, fontId: u8) void {
        self.cursor.fontId = fontId;
    }

    pub fn hr(self: *PDFDocument, thickness: f32) !void {
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

            try self.writer.putText(token, self.cursor.fontId, layouter.fontSize, self.pageProperties.documentBorder, y + layouter.getLineHeight() - layouter.getBaseline());
        }
        self.cursor.y = @intCast(y);
    }

    // todo: move this code to table?
    pub fn writeCell(self: *PDFDocument, table: *Table) !void {
        var remainingText = table.getCurrentCell().remainingText;
        var layouter = try Layouter.init(remainingText, table.getCurrentCell().width - 2 * table.padding, self.cursor.fontSize, self.cursor.fontId);
        var y: i32 = table.currentRowY;
        while (layouter.nextLine()) |token| {
            // advance cursor by this new line, breaking loop if we run out of text
            y -= layouter.getLineHeight();
            if (y + layouter.getLineGap() < self.pageProperties.getContentBottom()) {
                table.getCurrentCell().remainingText = remainingText;
                table.currentColumn += 1;
                return;
            }

            try self.writer.putText(token, self.cursor.fontId, layouter.fontSize, table.getCurrentCell().x + table.padding, y - table.padding + 1);
            remainingText = layouter.remainingText();
            table.getCurrentCell().height = @intCast(table.currentRowY - y + 2 * table.padding + layouter.getLineHeight() - layouter.getBaseline());
        }
        table.getCurrentCell().remainingText.len = 0;
        table.currentColumn += 1;
    }

    pub fn writeRow(self: *PDFDocument, strings: []const []const u8) !void {
        for (self.table.getCells(), strings) |*cell, string| {
            cell.remainingText = string;
        }
        try self.writeCells(&self.table);
        try self.table.finishRow(&self.writer);

        // handle page breaks if necessary
        while (!self.table.isRowDone()) {
            try self.table.finishTable(&self.writer);
            try self.writer.newPage(self.pageProperties.width, self.pageProperties.height);
            self.table.y = self.pageProperties.getContentTop();
            self.table.currentRowY = self.table.y;

            try self.writeCells(&self.table);
            try self.table.finishRow(&self.writer);
        }
    }

    pub fn startTable(self: *PDFDocument, columnWidths: []const u16) void {
        self.table = Table.init(columnWidths, self.pageProperties.getContentLeft(), self.cursor.y);
    }

    pub inline fn finishTable(self: *PDFDocument) !void {
        try self.table.finishTable(&self.writer);
    }

    fn writeCells(self: *PDFDocument, table: *Table) !void {
        for (table.getCells()) |cell| {
            _ = cell;
            try self.writeCell(table);
        }
    }

    fn resetCursor(self: *PDFDocument) void {
        self.cursor.x = self.pageProperties.documentBorder;
        self.cursor.y = self.pageProperties.getContentTop();
        self.cursor.fontSize = 12;
        self.cursor.fontId = PredefinedFonts.helveticaRegular;
    }
};

test "write simple pdf to disk" {
    std.testing.log_level = .info;
    var document = PDFDocument.init(std.heap.page_allocator);
    defer document.deinit();

    try document.setupDocument(PageFormat.A4, PageOrientation.PORTRAIT);

    {
        document.setFontById(PredefinedFonts.helveticaBold);
        document.setFontSize(36);
        try document.addText("PDF-Nano");
        try document.hr(1.5);

        document.advanceCursor(15);
        document.setFontById(PredefinedFonts.helveticaRegular);
        document.setFontSize(12);
        try document.addText("PDF-Nano is a tiny pdf library for projects where storage space is limited. The goal is to support as many features as possible while staying below ~64kB.");

        document.advanceCursor(15);
        document.setFontById(PredefinedFonts.helveticaBold);
        document.setFontSize(18);
        try document.addText("Done:");

        document.advanceCursor(5);
        document.setFontById(PredefinedFonts.helveticaRegular);
        document.setFontSize(12);
        try document.addText("· Basic Fonts/Text/Pages");
        try document.addText("· Umlaut: äöü èàé");
        try document.addText("· Lines");
        try document.addText("· Tables");

        document.advanceCursor(15);
        document.setFontById(PredefinedFonts.helveticaBold);
        document.setFontSize(18);
        try document.addText("Todo:");

        document.advanceCursor(5);
        document.setFontById(PredefinedFonts.helveticaRegular);
        document.setFontSize(12);
        try document.addText("· Colors/Background Fill");
        try document.addText("· Right Align/Justify Text");

        document.advanceCursor(15);
        const cols = [_]u16{ 100, 100, 100 };
        document.startTable(&cols);

        document.setFontById(PredefinedFonts.helveticaBold);
        const strings = [_][]const u8{ "one", "two", "three" };
        try document.writeRow(&strings);
        try document.finishTable();
    }

    var result = try document.render();
    try std.testing.expect(result.len > 5);
    const out_file = try std.fs.cwd().createFile("zig-out/lib/test.pdf", .{});
    defer out_file.close();
    var buf_writer = std.io.bufferedWriter(out_file.writer());
    var stream_writer = buf_writer.writer();
    try stream_writer.writeAll(result);
    _ = try buf_writer.flush();
}

test "check enums" {
    try std.testing.expectEqual(PageFormat.LETTER, @as(PageFormat, @enumFromInt(0)));
    try std.testing.expectEqual(PageFormat.A4, @as(PageFormat, @enumFromInt(1)));

    try std.testing.expectEqual(PageOrientation.PORTRAIT, @as(PageOrientation, @enumFromInt(0)));
    try std.testing.expectEqual(PageOrientation.LANDSCAPE, @as(PageOrientation, @enumFromInt(1)));
}
