const std = @import("std");
const PDFWriter = @import("writer.zig").PDFWriter;
const Color = @import("writer.zig").Color;
const Font = @import("font.zig").Font;
const PredefinedFonts = @import("font.zig").PredefinedFonts;
const Layouter = @import("layouter.zig").Layouter;
const TextAlignment = @import("layouter.zig").TextAlignment;
const Table = @import("table.zig").Table;
const PageProperties = @import("page_properties.zig").PageProperties;

pub const pdf_nano_version: [:0]const u8 = "0.8.0";

pub const PageOrientation = enum(c_uint) { PORTRAIT, LANDSCAPE };
pub const PageFormat = enum(c_uint) { LETTER, A4 };

/// Common page formats
const formats = [_][2]u16{
    [2]u16{ 612, 792 },
    [2]u16{ 595, 842 },
};

// Text style and related stuff
pub const Style = struct {
    font_size: u16,
    font: *const Font,
    font_color: Color, // Text + Fill
    stroke_color: Color, // Lines / Strokes
    fill_color: Color, // Brackground (e.g. table cell bg)
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
    page_properties: PageProperties = undefined,
    cursor: Cursor = undefined,
    table: Table = undefined,
    stream_pos: usize = undefined,

    pub fn init(allocator: std.mem.Allocator) PDFDocument {
        return PDFDocument{
            .writer = PDFWriter.init(allocator),
            .page_properties = PageProperties{},
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
        self.page_properties.width = formats[@intFromEnum(format)][0 + @intFromEnum(orientation)];
        self.page_properties.height = formats[@intFromEnum(format)][1 - @intFromEnum(orientation)];
        try self.writer.startDocument(self.page_properties.width, self.page_properties.height);
        self.resetCursorPos();
        self.setDefaultStyle();
    }

    pub fn showPageNumbers(self: *PDFDocument, alignment: TextAlignment, font_size: u8) !void {
        self.page_properties.footer = .PAGE_NUMBER;
        self.page_properties.footer_style.alignment = alignment;
        self.page_properties.footer_style.font_size = font_size;
        try self.addFooter();
    }

    pub fn breakPage(self: *PDFDocument) !void {
        try self.writer.newPage(self.page_properties.width, self.page_properties.height);
        try self.addFooter();
        self.cursor.y = self.page_properties.getContentTop();
        try self.writer.setColor(self.cursor.style.font_color);
        try self.writer.setStrokeColor(self.cursor.style.stroke_color);
    }

    pub fn advanceCursor(self: *PDFDocument, y: u16) void {
        self.cursor.y -= y;
    }

    pub fn setFontSize(self: *PDFDocument, font_size: u8) void {
        self.cursor.style.font_size = font_size;
    }

    pub fn setFont(self: *PDFDocument, font: *const Font) void {
        self.cursor.style.font = font;
    }

    pub fn setFontColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.style.font_color = Color{ .r = r, .g = g, .b = b };
    }

    pub fn setStrokeColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.style.stroke_color = Color{ .r = r, .g = g, .b = b };
    }

    pub fn setFillColor(self: *PDFDocument, r: f32, g: f32, b: f32) void {
        self.cursor.style.fill_color = Color{ .r = r, .g = g, .b = b };
    }

    pub fn hr(self: *PDFDocument, thickness: f32) !void {
        try self.writer.setStrokeColor(self.cursor.style.stroke_color);
        try self.writer.putLine(thickness, self.page_properties.getContentLeft(), self.cursor.y, self.page_properties.getContentRight(), self.cursor.y);
    }

    pub fn setTextAlignment(self: *PDFDocument, alignment: TextAlignment) void {
        self.cursor.style.alignment = alignment;
    }

    pub fn addText(self: *PDFDocument, text: []const u8) !void {
        var layouter = try Layouter.init(
            text,
            self.page_properties.getContentLeft(),
            self.page_properties.getContentWidth(),
            self.cursor.style,
        );
        var y: i32 = self.cursor.y;
        while (layouter.nextLine()) |line| {
            // advance cursor by this new line, creating new page if necessary
            y -= layouter.getLineHeight();
            if (y + layouter.getLineGap() < self.page_properties.getContentBottom()) {
                self.resetCursorPos();
                try self.writer.newPage(self.page_properties.width, self.page_properties.height);
                try self.addFooter();
                y = self.page_properties.getContentTop() - layouter.getLineHeight();
            }

            try self.writer.setColor(self.cursor.style.font_color);
            try layouter.layoutLine(line, y + layouter.getLineHeight() - layouter.getBaseline(), &self.writer);
            //try self.writer.putText(line, self.cursor.fontId, layouter.fontSize, self.pageProperties.documentBorder, y + layouter.getLineHeight() - layouter.getBaseline());
        }
        self.cursor.y = @intCast(y);
    }

    pub fn writeRow(self: *PDFDocument, strings: []const []const u8) !void {
        try self.writer.setStrokeColor(self.cursor.style.stroke_color);
        for (self.table.getCells(), strings) |*cell, string| {
            cell.remaining_text = string;
        }
        try self.table.writeRow(self);

        // handle page breaks if necessary
        while (!self.table.isRowDone()) {
            _ = try self.table.finishTable(&self.writer);
            try self.writer.newPage(self.page_properties.width, self.page_properties.height);
            try self.addFooter();
            self.table.y = self.page_properties.getContentTop();
            self.table.current_row_y = self.table.y;

            if (self.table.hasHeaders() and self.table.repeat) {
                try self.table.writeHeaderRow(self);
            }
            try self.table.writeRow(self);
        }
    }

    pub fn startTable(self: *PDFDocument, column_widths: []const u16) void {
        self.table.startTable(column_widths, self.page_properties.getContentLeft(), self.cursor.y);
    }

    /// Can only be called after startTable() and before first writeRow() for a given table
    /// Sets and immediately renders table headers
    /// Multiple calls to setTableHeaders() per table is not supported
    pub fn setTableHeaders(self: *PDFDocument, headers: []const []const u8, repeat_per_page: bool) !void {
        try self.table.setHeaders(headers, repeat_per_page);
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
        var buffer: [1024]u8 = undefined;
        var buf_writer = out_file.writer(&buffer);
        _ = try buf_writer.interface.write(try doc.render());
        _ = try buf_writer.interface.flush();
    }

    fn resetCursorPos(self: *PDFDocument) void {
        self.cursor.x = self.page_properties.document_border;
        self.cursor.y = self.page_properties.getContentTop();
    }

    fn setDefaultStyle(self: *PDFDocument) void {
        self.cursor.style = .{
            .font_size = 12,
            .font = PredefinedFonts.helvetica_regular,
            .font_color = Color.BLACK,
            .stroke_color = Color.BLACK,
            .fill_color = Color.WHITE,
            .alignment = TextAlignment.LEFT,
        };
    }

    fn addFooter(self: *PDFDocument) !void {
        switch (self.page_properties.footer) {
            .PAGE_NUMBER => {
                var buf: [32]u8 = undefined;
                const text = try std.fmt.bufPrint(&buf, "{d}", .{self.writer.getCurrentPageNumber()});
                var layouter = try Layouter.init(
                    text,
                    self.page_properties.getContentLeft(),
                    self.page_properties.getContentWidth(),
                    self.page_properties.footer_style,
                );
                const someOffset = 5; // TODO: use font metrics to vertical align properly
                try layouter.layoutLine(layouter.nextLine() orelse unreachable, self.page_properties.getContentBottom() - self.page_properties.footer_style.font_size - someOffset, &self.writer);
            },
            else => {
                return;
            },
        }
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
