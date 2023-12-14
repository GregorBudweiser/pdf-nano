const PDFWriter = @import("writer.zig").PDFWriter;
const Color = @import("writer.zig").Color;
const std = @import("std");
const PDFDocument = @import("document.zig").PDFDocument;
const Layouter = @import("layouter.zig").Layouter;

/// Helper class to render a table
pub const Table = struct {
    const Cell = struct {
        x: u16 = 0,
        width: u16 = 0,
        height: u16 = 0,
        remainingText: []const u8 = undefined,
    };

    columns: [16]Cell = [1]Cell{Cell{}} ** 16,
    numCols: u8 = undefined,
    currentColumn: u8 = undefined,
    currentRowY: u16 = undefined,
    y: u16 = undefined,
    x: u16 = undefined,
    width: u16 = undefined,
    padding: u16 = undefined,
    lineWidth: f32 = undefined,

    /// @param columnWidths array of column widths. Max 16 elements supported
    pub fn init(columnWidths: []const u16, x: u16, y: u16) Table {
        // TODO: handle @intCast
        var table = Table{ .x = x, .y = y, .currentRowY = y, .currentColumn = 0, .numCols = @intCast(columnWidths.len), .lineWidth = 0.5, .padding = 4 };
        var currentX = x;
        for (table.getCells(), columnWidths) |*cell, width| {
            cell.width = width;
            cell.x = currentX;
            currentX += width;
        }
        table.width = currentX - x;
        return table;
    }

    pub fn writeRow(self: *Table, doc: *PDFDocument) !void {
        const y = self.currentRowY;
        var marker = doc.writer.createMarker();
        for (self.getCells()) |*cell| {
            try self.writeCell(doc, cell, &doc.writer);
        }
        try self.finishRow(&doc.writer);

        // Rendered/inserted before actuall cells
        var stringBuffer = [_]u8{0} ** 128;
        var alloc = std.heap.FixedBufferAllocator.init(&stringBuffer);
        var writer = PDFWriter.init(alloc.allocator());
        try writer.setColor(doc.cursor.fillColor);
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

    fn writeCell(self: *Table, doc: *PDFDocument, cell: *Cell, writer: *PDFWriter) !void {
        var remainingText = cell.remainingText;
        var layouter = try Layouter.init(remainingText, cell.width - 2 * self.padding, doc.cursor.fontSize, doc.cursor.fontId);
        var y: i32 = self.currentRowY;
        while (layouter.nextLine()) |token| {
            // advance cursor by this new line, breaking loop if we run out of text
            y -= layouter.getLineHeight();
            if (y + layouter.getLineGap() < doc.pageProperties.getContentBottom()) {
                cell.remainingText = remainingText;
                self.currentColumn += 1;
                return;
            }

            try writer.setColor(doc.cursor.fontColor);
            try writer.putText(token, doc.cursor.fontId, layouter.fontSize, self.getCurrentCell().x + self.padding, y - self.padding + 1);
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
