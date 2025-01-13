const std = @import("std");
const layout = @import("layouter.zig");
const font = @import("font.zig");
const testing = std.testing;

/// PDF float rgb values
pub const Color = struct { r: f32, g: f32, b: f32 };

/// Low level pdf writer handling the pdf format specific stuff
pub const PDFWriter = struct {
    /// pdf output buffer
    buffer: std.ArrayList(u8),

    /// byte offsets of the indirect references
    iRefOffsets: std.ArrayList(usize),

    /// list of all pages written
    pageIds: std.ArrayList(usize),

    /// page tree object
    pageTreeId: usize = undefined,

    /// current page object
    currentPage: PageDef = undefined,

    // font ids
    fonts: [font.predefinedFonts.len]usize = undefined,

    /// Definition of a pdf stream object
    const StreamDef = struct {
        /// byte offset of stream's length value
        lengthStart: usize,

        /// byte offset of stream's content
        streamStart: usize,
    };

    /// Definition of a pdf page object
    const PageDef = struct {
        /// stream def
        stream: StreamDef,

        /// object reference id
        pageId: usize,

        /// page width in dots (1/72th inch)
        width: u16,

        /// page height in dots (1/72th inch)
        height: u16,
    };

    pub fn init(allocator: std.mem.Allocator) PDFWriter {
        return PDFWriter{
            .buffer = std.ArrayList(u8).init(allocator),
            .iRefOffsets = std.ArrayList(usize).init(allocator),
            .pageIds = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *PDFWriter) void {
        self.buffer.deinit();
        self.iRefOffsets.deinit();
    }

    pub fn startDocument(self: *PDFWriter, pageWidth: u16, pageHeight: u16) !void {
        _ = try self.createIRefID(); // use up objectId 0 and ignore it.
        try self.buffer.appendSlice("%PDF-1.6\n"); // write header

        const fonts = [_][]const u8{ "Helvetica", "Helvetica-Bold", "Courier" };
        for (fonts, 0..) |f, i| {
            self.fonts[i] = try self.startObject();
            try self.appendFormatted("<<\n/Type /Font\n/Subtype /Type1\n/Name /F{d}\n/BaseFont /{s}\n/Encoding /WinAnsiEncoding\n>>\n", .{ i + 1, f });
            try self.endObject();
        }

        self.pageTreeId = try self.createIRefID();
        self.currentPage = try self.startPage(pageWidth, pageHeight);
    }

    /// Calling endDocument() "finishes" the document.
    /// After that, any changes to the pdf document will not generate a valid pdf file.
    pub fn endDocument(self: *PDFWriter) !void {
        try self.endPage(self.currentPage, self.pageTreeId);
        try self.writePageTree(self.pageIds.items, self.pageTreeId);
        const catalogId = try self.writeCatalog(self.pageTreeId);
        const xrefOffset = try self.writeXRef();
        try self.writeTrailer(xrefOffset, catalogId);
    }

    pub fn newPage(self: *PDFWriter, pageWidth: u16, pageHeight: u16) !void {
        try self.endPage(self.currentPage, self.pageTreeId);
        self.currentPage = try self.startPage(pageWidth, pageHeight);
    }

    pub fn putText(self: *PDFWriter, text: []const u8, fontId: u16, fontSize: u16, x: i32, y: i32) !void {
        try self.appendFormatted("BT\n/F{d} {d} Tf\n{d} {d} Td\n(", .{ fontId, fontSize, x, y });
        var iter = (try std.unicode.Utf8View.init(text)).iterator();
        while (iter.nextCodepoint()) |code| {
            // TODO: innermost loop.. optimize this..
            if (code == '(' or code == ')' or code == '\\' or code == '\t') {
                try self.buffer.append('\\');
            }

            if (code < 128) {
                try self.buffer.append(@intCast(code));
            } else {
                // note: we set font to WinAnsiEncoding.. seems to be utf-16 so this works for all 2-byte characters
                try self.appendFormatted("\\{o:3}", .{code});
            }
        }
        try self.append(") Tj\nET\n");
    }

    pub fn putLine(self: *PDFWriter, w: f32, x0: i32, y0: i32, x1: i32, y1: i32) !void {
        try self.appendFormatted("{d:.3} w\n{d} {d} m\n{d} {d} l\nS\n", .{ w, x0, y0, x1, y1 });
    }

    pub fn putRect(self: *PDFWriter, x: i32, y: i32, w: i32, h: i32) !void {
        try self.appendFormatted("{d} {d} {d} {d} re\nf\n", .{ x, y, w, h });
    }

    pub fn setColor(self: *PDFWriter, color: Color) !void {
        try self.appendFormatted("{d:.3} {d:.3} {d:.3} rg\n", .{ color.r, color.g, color.b });
    }

    pub fn setStrokeColor(self: *PDFWriter, color: Color) !void {
        try self.appendFormatted("{d:.3} {d:.3} {d:.3} RG\n", .{ color.r, color.g, color.b });
    }

    /// Get a marker/pointer to the current output to later insert stuff here
    /// This helps build stuff that depends on the rendering order without
    /// a dynamic intermediate representation of the pdf file.
    pub fn createMarker(self: *const PDFWriter) usize {
        // TODO: track and handle iRefIds once necessary
        return getEncodedBytes(self);
    }

    pub fn insertAtMarker(self: *PDFWriter, marker: usize, data: []const u8) !void {
        try self.buffer.insertSlice(marker, data);
    }

    fn writeCatalog(self: *PDFWriter, pageTreeId: usize) !usize {
        const catalogId = try self.startObject();
        try self.appendFormatted("<<\n/Type /Catalog\n/Pages {d} 0 R\n>>\n", .{pageTreeId});
        try self.endObject();
        return catalogId;
    }

    fn startPage(self: *PDFWriter, pageWidth: u16, pageHeight: u16) !PageDef {
        const pageId = try self.startObject();
        const stream = try self.startStream();
        return PageDef{ .stream = stream, .pageId = pageId, .width = pageWidth, .height = pageHeight };
    }

    fn endPage(self: *PDFWriter, page: PageDef, pageTreeId: usize) !void {
        try self.endStream(page.stream);
        try self.endObject();

        // TODO: automate fonts ids..
        const pageId = try self.startObject();
        const pageString =
            \\<<
            \\/Type /Page
            \\/Parent {d} 0 R
            \\/Resources <<
            \\ /Font <<
            \\  /F1 {d} 0 R
            \\  /F2 {d} 0 R
            \\  /F3 {d} 0 R
            \\ >>
            \\>>
            \\/MediaBox [0 0 {d} {d}]
            \\/Contents {d} 0 R
            \\>>
            \\
        ;
        try self.appendFormatted(pageString, .{ pageTreeId, self.fonts[0], self.fonts[1], self.fonts[2], page.width, page.height, page.pageId });
        try self.endObject();
        try self.pageIds.append(pageId);
    }

    fn writePageTree(self: *PDFWriter, pageIds: []const usize, pageTreeId: usize) !void {
        try self.startObjectWithId(pageTreeId);
        try self.append("<<\n/Type /Pages\n/Kids [\n");
        for (pageIds) |pageId| {
            try self.appendFormatted("   {d} 0 R\n", .{pageId});
        }
        try self.appendFormatted("]\n/Count {d}\n>>\n", .{pageIds.len});
        try self.endObject();
    }

    fn writeXRef(self: *PDFWriter) !usize {
        const xrefOffset = self.getEncodedBytes();
        try self.buffer.appendSlice("xref\n");
        const N = self.iRefOffsets.items.len;
        try self.appendFormatted("{d} {d}\n", .{ 0, N });

        // objectId 0 is invalid.. but must be in xref..  the pdf spec is WEIRD!
        try self.append("0000000000 65535 f \n");
        var i: u32 = 1;
        while (i < N) : (i += 1) {
            try self.appendFormatted("{d:0>10} 00000 n \n", .{self.iRefOffsets.items[i]});
        }
        return xrefOffset;
    }

    fn writeTrailer(self: *PDFWriter, xrefOffset: usize, catalogId: usize) !void {
        const trailerString =
            \\trailer
            \\<<
            \\/Size {d}
            \\/Root {d} 0 R
            \\>>
            \\startxref
            \\{d}
            \\%%EOF
        ;
        try self.appendFormatted(trailerString, .{ self.iRefOffsets.items.len, catalogId, xrefOffset });
    }

    // pdf-specific utility functions ========================================================================

    fn startStream(self: *PDFWriter) !StreamDef {
        try self.append("<< /Length ");
        const lengthStart = self.getEncodedBytes();
        try self.append("          "); // insert rendered length here; avoids move

        try self.append(" >>\nstream\r\n"); // needs \r or \r\n by spec
        const streamStart = self.getEncodedBytes();

        return StreamDef{ .lengthStart = lengthStart, .streamStart = streamStart };
    }

    fn endStream(self: *PDFWriter, stream: StreamDef) !void {
        const streamEnd = self.getEncodedBytes();
        try self.replaceFormatted(32, stream.lengthStart, "{d}", .{streamEnd - stream.streamStart});
        try self.append("endstream\n");
    }

    fn startObject(self: *PDFWriter) !usize {
        const iRefId = try self.createIRefID();
        try self.appendFormatted("{d} 0 obj\n", .{iRefId});
        return iRefId;
    }

    fn startObjectWithId(self: *PDFWriter, iRefId: usize) !void {
        self.iRefOffsets.items[iRefId] = self.getEncodedBytes();
        try self.appendFormatted("{d} 0 obj\n", .{iRefId});
    }

    fn endObject(self: *PDFWriter) !void {
        try self.append("endobj\n");
    }

    fn getEncodedBytes(self: *const PDFWriter) usize {
        return self.buffer.items.len;
    }

    fn createIRefID(self: *PDFWriter) !usize {
        const iRefId = self.iRefOffsets.items.len;
        try self.iRefOffsets.append(self.getEncodedBytes());
        return iRefId;
    }

    // pdf-agnostic utility functions ===============================================================

    fn appendFormatted(self: *PDFWriter, comptime format: []const u8, args: anytype) !void {
        try self.buffer.writer().print(format, args);
    }

    fn replaceFormatted(self: *PDFWriter, comptime size: u32, pos: usize, comptime format: []const u8, args: anytype) !void {
        var stringBuffer = [_]u8{0} ** size;
        var bufferedWriter = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &stringBuffer };
        try bufferedWriter.writer().print(format, args);
        try self.buffer.replaceRange(pos, bufferedWriter.pos, stringBuffer[0..bufferedWriter.pos]);
    }

    fn append(self: *PDFWriter, string: []const u8) !void {
        try self.buffer.appendSlice(string);
    }
};

test "init deinit" {
    std.testing.log_level = .info;
    var writer = PDFWriter.init(std.heap.page_allocator);
    defer writer.deinit();

    try testing.expect(writer.buffer.items.len == 0);
}
