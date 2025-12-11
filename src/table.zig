const PDFWriter = @import("writer.zig").PDFWriter;
const Color = @import("writer.zig").Color;
const std = @import("std");
const PDFDocument = @import("document.zig").PDFDocument;
const Layouter = @import("layouter.zig").Layouter;
const Style = @import("document.zig").Style;
const TextAlignment = @import("layouter.zig").TextAlignment;
const PredefinedFonts = @import("font.zig").PredefinedFonts;

const MAX_COL: u8 = 16;

/// Helper class to render a table
pub const Table = struct {
    const Cell = struct {
        x: u16 = 0,
        width: u16 = 0,
        height: u16 = 0,
        remaining_text: []const u8 = undefined,
    };

    columns: [MAX_COL]Cell = [1]Cell{Cell{}} ** MAX_COL,
    numCols: u8 = undefined,
    current_column: u8 = undefined,
    current_row_y: u16 = undefined,
    y: u16 = undefined,
    x: u16 = undefined,
    width: u16 = undefined,
    padding: u16 = undefined,
    line_width: f32 = undefined,
    headers: std.array_list.Managed([]const u8) = undefined,
    repeat: bool = undefined,
    header_style: Style = undefined, // TODO default init

    pub fn init(allocator: std.mem.Allocator) Table {
        return Table{
            .headers = std.array_list.Managed([]const u8).init(allocator),
            .repeat = false,
            .header_style = Style{
                .alignment = TextAlignment.LEFT,
                .font = PredefinedFonts.helvetica_bold,
                .font_size = 12,
                .font_color = Color.BLACK,
                .stroke_color = Color.BLACK,
                .fill_color = Color.GREY,
            },
        };
    }

    pub fn deinit(self: *Table) void {
        self.headers.deinit();
    }

    pub fn setHeaderStyle(self: *Table, style: Style) void {
        self.header_style = style;
    }

    pub fn setHeaders(self: *Table, headers: []const []const u8, repeat_per_page: bool) !void {
        self.repeat = repeat_per_page;
        self.headers.clearAndFree();
        for (headers) |header| {
            const copy = try self.headers.allocator.dupe(u8, header);
            try self.headers.append(copy);
        }
    }

    pub fn hasHeaders(self: *const Table) bool {
        return self.headers.items.len > 0;
    }

    /// @param columnWidths array of column widths. Max MAX_COL elements supported
    pub fn startTable(self: *Table, column_widths: []const u16, x: u16, y: u16) void {
        self.x = x;
        self.y = y;
        self.current_row_y = y;
        self.current_column = 0;
        self.numCols = @intCast(@min(MAX_COL, column_widths.len));
        self.line_width = 0.5;
        self.padding = 4;

        var currentX = x;
        for (self.getCells(), column_widths) |*cell, width| {
            cell.width = width;
            cell.x = currentX;
            currentX += width;
        }
        self.width = currentX - x;
    }

    pub fn writeHeaderRow(self: *Table, doc: *PDFDocument) !void {
        if (!try self.canFitNextRow(doc)) {
            return;
        }

        try doc.writer.setStrokeColor(self.header_style.stroke_color);
        const y = self.current_row_y;
        const marker = doc.writer.createMarker();
        for (self.getCells(), self.headers.items) |*cell, headerText| {
            var headerCell = cell.*;
            headerCell.remaining_text = headerText;
            try self.writeCellWithStyle(doc, &headerCell, &doc.writer, self.header_style);
            headerCell.remaining_text = cell.remaining_text;
            cell.* = headerCell;
        }
        try self.finishRow(&doc.writer);

        // Background needs to be rendered/inserted before actual cells
        // but we only know cell height after we rendered them..
        var string_buffer = [_]u8{0} ** 128;
        var alloc = std.heap.FixedBufferAllocator.init(&string_buffer);
        var writer = PDFWriter.init(alloc.allocator());
        try writer.setColor(self.header_style.fill_color);
        try writer.putRect(self.x, y, self.width, -@as(i32, y - self.current_row_y));

        try doc.writer.insertAtMarker(marker, writer.buffer.items);
    }

    pub fn writeRow(self: *Table, doc: *PDFDocument) !void {
        if (!try self.canFitNextRow(doc)) {
            return;
        }

        const y = self.current_row_y;
        const marker = doc.writer.createMarker();
        for (self.getCells()) |*cell| {
            try self.writeCell(doc, cell, &doc.writer);
        }
        try self.finishRow(&doc.writer);

        // Background needs to be rendered/inserted before actual cells
        // but we only know cell height after we rendered them..
        var string_buffer = [_]u8{0} ** 128;
        var alloc = std.heap.FixedBufferAllocator.init(&string_buffer);
        var writer = PDFWriter.init(alloc.allocator());
        try writer.setColor(doc.cursor.style.fill_color);
        try writer.putRect(self.x, y, self.width, -@as(i32, y - self.current_row_y));

        try doc.writer.insertAtMarker(marker, writer.buffer.items);
    }

    /// get configured cells for this table
    pub fn getCells(self: *Table) []Cell {
        return self.columns[0..self.numCols];
    }

    /// @returns the currently active cell
    pub fn getCurrentCell(self: *Table) *Cell {
        return &self.columns[self.current_column];
    }

    /// Return false if some text did not fit page and needs to
    /// be continued on next page
    pub fn isRowDone(self: *const Table) bool {
        for (self.columns[0..self.numCols]) |cell| {
            if (cell.remaining_text.len != 0) {
                return false;
            }
        }
        return true;
    }

    /// assumes finishRow() was called before
    /// @returns y end-coordinate of table bounds
    pub fn finishTable(self: *Table, writer: *PDFWriter) !u16 {
        // top
        try writer.putLine(self.line_width, self.x, self.current_row_y, self.x + self.width, self.current_row_y);

        // horizontal lines, left of each column
        for (self.getCells()) |cell| {
            try writer.putLine(self.line_width, cell.x, self.y, cell.x, self.current_row_y);
        }
        try writer.putLine(self.line_width, self.x + self.width, self.y, self.x + self.width, self.current_row_y);

        return self.current_row_y;
    }

    fn canFitNextRow(self: *const Table, doc: *PDFDocument) !bool {
        const layouter = try Layouter.init("", self.padding, 100, doc.cursor.style);
        const y: i32 = self.current_row_y - layouter.getLineHeight();
        return y + layouter.getLineGap() - 2 * self.padding >= doc.page_properties.getContentBottom();
    }

    fn writeCell(self: *Table, doc: *PDFDocument, cell: *Cell, writer: *PDFWriter) !void {
        try self.writeCellWithStyle(doc, cell, writer, doc.cursor.style);
    }

    fn writeCellWithStyle(self: *Table, doc: *PDFDocument, cell: *Cell, writer: *PDFWriter, style: Style) !void {
        var remaining_text = cell.remaining_text;
        var layouter = try Layouter.init(remaining_text, cell.x + self.padding, cell.width - 2 * self.padding, style);
        var y: i32 = self.current_row_y;
        while (layouter.nextLine()) |token| {
            // advance cursor by this new line, breaking loop if we run out of space
            y -= layouter.getLineHeight();
            if (y + layouter.getLineGap() < doc.page_properties.getContentBottom()) {
                cell.remaining_text = remaining_text;
                self.current_column += 1;
                return;
            }

            try writer.setColor(style.font_color);
            try layouter.layoutLine(token, y - self.padding + 1, writer);
            remaining_text = layouter.remainingText();
            cell.height = @intCast(self.current_row_y - y + 2 * self.padding + layouter.getLineHeight() - layouter.getBaseline());
        }
        cell.remaining_text.len = 0;
        self.current_column += 1;
    }

    /// renders bottom line of current row, computes and updates total height info
    fn finishRow(self: *Table, writer: *PDFWriter) !void {
        try writer.putLine(self.line_width, self.x, self.current_row_y, self.x + self.width, self.current_row_y);
        var max_height: u16 = 0;
        for (self.getCells()) |cell| {
            max_height = @max(max_height, cell.height);
        }
        self.current_row_y -= max_height;
        self.current_column = 0;
    }
};
