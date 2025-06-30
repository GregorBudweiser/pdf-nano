const std = @import("std");
const PDFWriter = @import("writer.zig").PDFWriter;
const Color = @import("writer.zig").Color;
const Font = @import("font.zig").Font;
const PredefinedFonts = @import("font.zig").PredefinedFonts;
const Layouter = @import("layouter.zig").Layouter;
const TextAlignment = @import("layouter.zig").TextAlignment;
const Table = @import("table.zig").Table;
const PageProperties = @import("page_properties.zig").PageProperties;

pub const PDF_NANO_VERSION: [:0]const u8 = "0.6.0";

pub const PageOrientation = enum(c_uint) { PORTRAIT, LANDSCAPE };
pub const PageFormat = enum(c_uint) { LETTER, A4 };

/// Common page formats
const formats = [_][2]u16{
    [2]u16{ 612, 792 },
    [2]u16{ 595, 842 },
};

// Text style and related stuff
pub const Style = struct {
    fontSize: u16,
    font: *const Font,
    fontColor: Color, // Text + Fill
    strokeColor: Color, // Lines / Strokes
    fillColor: Color, // Brackground (e.g. table cell bg)
    alignment: TextAlignment,
};

/// Virtual cursor inside document
const Cursor = struct {
    x: u16,
    y: u16,
    style: Style,
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
            .table = Table.init(allocator),
        };
    }

    pub fn deinit(self: *PDFDocument) void {
        self.writer.deinit();
        self.table.deinit();
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
        self.resetCursorPos();
        self.setDefaultStyle();
    }

    pub fn breakPage(self: *PDFDocument) !void {
        try self.writer.newPage(self.pageProperties.width, self.pageProperties.height);
        self.cursor.y = self.pageProperties.getContentTop();
        try self.writer.setColor(self.cursor.style.fontColor);
        try self.writer.setStrokeColor(self.cursor.style.strokeColor);
    }

    pub fn advanceCursor(self: *PDFDocument, y: u16) void {
        self.cursor.y -= y;
    }

    pub fn setFontSize(self: *PDFDocument, fontSize: u8) void {
        self.cursor.style.fontSize = fontSize;
    }

    pub fn setFont(self: *PDFDocument, font: *const Font) void {
        self.cursor.style.font = font;
    }

    pub fn setFontColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.style.fontColor = Color{ .r = r, .g = g, .b = b };
    }

    pub fn setStrokeColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.style.strokeColor = Color{ .r = r, .g = g, .b = b };
    }

    pub fn setFillColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.style.fillColor = Color{ .r = r, .g = g, .b = b };
    }

    pub fn hr(self: *PDFDocument, thickness: f32) !void {
        try self.writer.setStrokeColor(self.cursor.style.strokeColor);
        try self.writer.putLine(thickness, self.pageProperties.getContentLeft(), self.cursor.y, self.pageProperties.getContentRight(), self.cursor.y);
    }

    pub fn setTextAlignment(self: *PDFDocument, alignment: TextAlignment) void {
        self.cursor.style.alignment = alignment;
    }

    pub fn addText(self: *PDFDocument, text: []const u8) !void {
        var layouter = try Layouter.init(
            text,
            self.pageProperties.getContentLeft(),
            self.pageProperties.getContentWidth(),
            self.cursor.style,
        );
        var y: i32 = self.cursor.y;
        while (layouter.nextLine()) |line| {
            // advance cursor by this new line, creating new page if necessary
            y -= layouter.getLineHeight();
            if (y + layouter.getLineGap() < self.pageProperties.getContentBottom()) {
                self.resetCursorPos();
                try self.writer.newPage(self.pageProperties.width, self.pageProperties.height);
                y = self.pageProperties.getContentTop() - layouter.getLineHeight();
            }

            try self.writer.setColor(self.cursor.style.fontColor);
            try layouter.layoutLine(line, y + layouter.getLineHeight() - layouter.getBaseline(), &self.writer);
            //try self.writer.putText(line, self.cursor.fontId, layouter.fontSize, self.pageProperties.documentBorder, y + layouter.getLineHeight() - layouter.getBaseline());
        }
        self.cursor.y = @intCast(y);
    }

    pub fn writeRow(self: *PDFDocument, strings: []const []const u8) !void {
        try self.writer.setStrokeColor(self.cursor.style.strokeColor);
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

            if (self.table.hasHeaders() and self.table.repeat) {
                try self.table.writeHeaderRow(self);
            }
            try self.table.writeRow(self);
        }
    }

    pub fn startTable(self: *PDFDocument, columnWidths: []const u16) void {
        self.table.startTable(columnWidths, self.pageProperties.getContentLeft(), self.cursor.y);
    }

    /// Can only be called after startTable() and before first writeRow() for a given table
    /// Sets and immediately renders table headers
    /// Multiple calls to setTableHeaders() per table is not supported
    pub fn setTableHeaders(self: *PDFDocument, headers: []const []const u8, repeatPerPage: bool) !void {
        try self.table.setHeaders(headers, repeatPerPage);
        try self.table.writeHeaderRow(self);
    }

    pub fn setTableHeaderStyle(self: *PDFDocument, style: Style) void {
        self.table.setHeaderStyle(style);
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

    fn resetCursorPos(self: *PDFDocument) void {
        self.cursor.x = self.pageProperties.documentBorder;
        self.cursor.y = self.pageProperties.getContentTop();
    }

    fn setDefaultStyle(self: *PDFDocument) void {
        self.cursor.style = .{
            .fontSize = 12,
            .font = PredefinedFonts.helveticaRegular,
            .fontColor = Color.BLACK,
            .strokeColor = Color.BLACK,
            .fillColor = Color.WHITE,
            .alignment = TextAlignment.LEFT,
        };
    }
};

test "create empty pdf" {
    std.testing.log_level = .info;
    var document = PDFDocument.init(std.heap.page_allocator);
    defer document.deinit();

    try document.setupDocument(PageFormat.A4, PageOrientation.PORTRAIT);

    const result = try document.render();
    try std.testing.expect(result.len > 0);
}

test "check enums" {
    try std.testing.expectEqual(PageFormat.LETTER, @as(PageFormat, @enumFromInt(0)));
    try std.testing.expectEqual(PageFormat.A4, @as(PageFormat, @enumFromInt(1)));

    try std.testing.expectEqual(PageOrientation.PORTRAIT, @as(PageOrientation, @enumFromInt(0)));
    try std.testing.expectEqual(PageOrientation.LANDSCAPE, @as(PageOrientation, @enumFromInt(1)));
}
