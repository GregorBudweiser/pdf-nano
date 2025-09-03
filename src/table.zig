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
        remainingText: []const u8 = undefined,
    };

    columns: [MAX_COL]Cell = [1]Cell{Cell{}} ** MAX_COL,
    numCols: u8 = undefined,
    currentColumn: u8 = undefined,
    currentRowY: u16 = undefined,
    y: u16 = undefined,
    x: u16 = undefined,
    width: u16 = undefined,
    padding: u16 = undefined,
    lineWidth: f32 = undefined,
    headers: std.array_list.Managed([]const u8) = undefined,
    repeat: bool = undefined,
    headerStyle: Style = undefined, // TODO default init

    pub fn init(allocator: std.mem.Allocator) Table {
        return Table{
            .headers = std.array_list.Managed([]const u8).init(allocator),
            .repeat = false,
            .headerStyle = Style{
                .alignment = TextAlignment.LEFT,
                .font = PredefinedFonts.helveticaBold,
                .fontSize = 12,
                .fontColor = Color.BLACK,
                .strokeColor = Color.BLACK,
                .fillColor = Color.GREY,
            },
        };
    }

    pub fn deinit(self: *Table) void {
        self.headers.deinit();
    }

    pub fn setHeaderStyle(self: *Table, style: Style) void {
        self.headerStyle = style;
    }

    pub fn setHeaders(self: *Table, headers: []const []const u8, repeatPerPage: bool) !void {
        self.repeat = repeatPerPage;
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
    pub fn startTable(self: *Table, columnWidths: []const u16, x: u16, y: u16) void {
        self.x = x;
        self.y = y;
        self.currentRowY = y;
        self.currentColumn = 0;
        self.numCols = @intCast(@min(MAX_COL, columnWidths.len));
        self.lineWidth = 0.5;
        self.padding = 4;

        var currentX = x;
        for (self.getCells(), columnWidths) |*cell, width| {
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

        try doc.writer.setStrokeColor(self.headerStyle.strokeColor);
        const y = self.currentRowY;
        const marker = doc.writer.createMarker();
        for (self.getCells(), self.headers.items) |*cell, headerText| {
            var headerCell = cell.*;
            headerCell.remainingText = headerText;
            try self.writeCellWithStyle(doc, &headerCell, &doc.writer, self.headerStyle);
            headerCell.remainingText = cell.remainingText;
            cell.* = headerCell;
        }
        try self.finishRow(&doc.writer);

        // Background needs to be rendered/inserted before actual cells
        // but we only know cell height after we rendered them..
        var stringBuffer = [_]u8{0} ** 128;
        var alloc = std.heap.FixedBufferAllocator.init(&stringBuffer);
        var writer = PDFWriter.init(alloc.allocator());
        try writer.setColor(self.headerStyle.fillColor);
        try writer.putRect(self.x, y, self.width, -@as(i32, y - self.currentRowY));

        try doc.writer.insertAtMarker(marker, writer.buffer.items);
    }

    pub fn writeRow(self: *Table, doc: *PDFDocument) !void {
        if (!try self.canFitNextRow(doc)) {
            return;
        }

        const y = self.currentRowY;
        const marker = doc.writer.createMarker();
        for (self.getCells()) |*cell| {
            try self.writeCell(doc, cell, &doc.writer);
        }
        try self.finishRow(&doc.writer);

        // Background needs to be rendered/inserted before actual cells
        // but we only know cell height after we rendered them..
        var stringBuffer = [_]u8{0} ** 128;
        var alloc = std.heap.FixedBufferAllocator.init(&stringBuffer);
        var writer = PDFWriter.init(alloc.allocator());
        try writer.setColor(doc.cursor.style.fillColor);
        try writer.putRect(self.x, y, self.width, -@as(i32, y - self.currentRowY));

        try doc.writer.insertAtMarker(marker, writer.buffer.items);
    }

    /// get configured cells for this table
    pub fn getCells(self: *Table) []Cell {
        return self.columns[0..self.numCols];
    }

    /// @returns the currently active cell
    pub fn getCurrentCell(self: *Table) *Cell {
        return &self.columns[self.currentColumn];
    }

    /// Return false if some text did not fit page and needs to
    /// be continued on next page
    pub fn isRowDone(self: *const Table) bool {
        for (self.columns[0..self.numCols]) |cell| {
            if (cell.remainingText.len != 0) {
                return false;
            }
        }
        return true;
    }

    /// assumes finishRow() was called before
    /// @returns y end-coordinate of table bounds
    pub fn finishTable(self: *Table, writer: *PDFWriter) !u16 {
        // top
        try writer.putLine(self.lineWidth, self.x, self.currentRowY, self.x + self.width, self.currentRowY);

        // horizontal lines, left of each column
        for (self.getCells()) |cell| {
            try writer.putLine(self.lineWidth, cell.x, self.y, cell.x, self.currentRowY);
        }
        try writer.putLine(self.lineWidth, self.x + self.width, self.y, self.x + self.width, self.currentRowY);

        return self.currentRowY;
    }

    fn canFitNextRow(self: *const Table, doc: *PDFDocument) !bool {
        const layouter = try Layouter.init("", self.padding, 100, doc.cursor.style);
        const y: i32 = self.currentRowY - layouter.getLineHeight();
        return y + layouter.getLineGap() - 2 * self.padding >= doc.pageProperties.getContentBottom();
    }

    fn writeCell(self: *Table, doc: *PDFDocument, cell: *Cell, writer: *PDFWriter) !void {
        try self.writeCellWithStyle(doc, cell, writer, doc.cursor.style);
    }

    fn writeCellWithStyle(self: *Table, doc: *PDFDocument, cell: *Cell, writer: *PDFWriter, style: Style) !void {
        var remainingText = cell.remainingText;
        var layouter = try Layouter.init(remainingText, cell.x + self.padding, cell.width - 2 * self.padding, style);
        var y: i32 = self.currentRowY;
        while (layouter.nextLine()) |token| {
            // advance cursor by this new line, breaking loop if we run out of space
            y -= layouter.getLineHeight();
            if (y + layouter.getLineGap() < doc.pageProperties.getContentBottom()) {
                cell.remainingText = remainingText;
                self.currentColumn += 1;
                return;
            }

            try writer.setColor(style.fontColor);
            try layouter.layoutLine(token, y - self.padding + 1, writer);
            remainingText = layouter.remainingText();
            cell.height = @intCast(self.currentRowY - y + 2 * self.padding + layouter.getLineHeight() - layouter.getBaseline());
        }
        cell.remainingText.len = 0;
        self.currentColumn += 1;
    }

    /// renders bottom line of current row, computes and updates total height info
    fn finishRow(self: *Table, writer: *PDFWriter) !void {
        try writer.putLine(self.lineWidth, self.x, self.currentRowY, self.x + self.width, self.currentRowY);
        var maxHeight: u16 = 0;
        for (self.getCells()) |cell| {
            maxHeight = @max(maxHeight, cell.height);
        }
        self.currentRowY -= maxHeight;
        self.currentColumn = 0;
    }
};
