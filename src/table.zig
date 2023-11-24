const PDFWriter = @import("writer.zig").PDFWriter;
const std = @import("std");

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

    /// renders bottom line of current row, computes and updates total height info
    pub fn finishRow(self: *Table, writer: *PDFWriter) !void {
        var maxHeight: u16 = 0;
        for (self.getCells()) |cell| {
            maxHeight = @max(maxHeight, cell.height);
        }
        self.currentRowY -= maxHeight;
        try writer.putLine(self.lineWidth, self.x, self.currentRowY, self.x + self.width, self.currentRowY);
        self.currentColumn = 0;
    }

    /// assumes finishRow() was called before
    pub fn finishTable(self: *Table, writer: *PDFWriter) !void {
        // top
        try writer.putLine(self.lineWidth, self.x, self.y, self.x + self.width, self.y);

        // horizontal lines, left of each column
        for (self.getCells()) |cell| {
            try writer.putLine(self.lineWidth, cell.x, self.y, cell.x, self.currentRowY);
        }
        try writer.putLine(self.lineWidth, self.x + self.width, self.y, self.x + self.width, self.currentRowY);
    }
};
