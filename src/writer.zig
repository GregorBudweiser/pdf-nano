const std = @import("std");
const layout = @import("layouter.zig");
const font = @import("font.zig");
const testing = std.testing;

/// PDF float rgb values
pub const Color = struct {
    pub const BLACK: Color = .{ .r = 0, .g = 0, .b = 0 };
    pub const WHITE: Color = .{ .r = 1, .g = 1, .b = 1 };
    pub const GREY: Color = .{ .r = 0.8, .g = 0.8, .b = 0.8 };

    r: f32,
    g: f32,
    b: f32,
};

/// Low level pdf writer handling the pdf format specific stuff
pub const PDFWriter = struct {
    /// pdf output buffer
    buffer: std.array_list.Managed(u8),

    /// byte offsets of the indirect references
    i_ref_offsets: std.array_list.Managed(usize),

    /// list of all pages written
    page_ids: std.array_list.Managed(usize),

    /// page tree object
    page_tree_id: usize = undefined,

    /// current page object
    current_page: PageDef = undefined,

    // font ids
    fonts: [font.predefined_fonts.len]usize = undefined,

    /// Definition of a pdf stream object
    const StreamDef = struct {
        /// byte offset of stream's length value
        length_start: usize,

        /// byte offset of stream's content
        stream_start: usize,
    };

    /// Definition of a pdf page object
    const PageDef = struct {
        /// stream def
        stream: StreamDef,

        /// object reference id
        page_id: usize,

        /// page width in dots (1/72th inch)
        width: u16,

        /// page height in dots (1/72th inch)
        height: u16,
    };

    pub fn init(allocator: std.mem.Allocator) PDFWriter {
        return PDFWriter{
            .buffer = std.array_list.Managed(u8).init(allocator),
            .i_ref_offsets = std.array_list.Managed(usize).init(allocator),
            .page_ids = std.array_list.Managed(usize).init(allocator),
        };
    }

    pub fn deinit(self: *PDFWriter) void {
        self.buffer.deinit();
        self.i_ref_offsets.deinit();
    }

    pub fn startDocument(self: *PDFWriter, page_width: u16, page_height: u16) !void {
        _ = try self.createIRefID(); // use up objectId 0 and ignore it.
        try self.buffer.appendSlice("%PDF-1.6\n"); // write header

        for (font.predefined_fonts, 0..) |f, i| {
            self.fonts[i] = try self.startObject();
            try self.appendFormatted("<<\n/Type /Font\n/Subtype /Type1\n/Name /F{d}\n/BaseFont /{s}\n/Encoding /WinAnsiEncoding\n>>\n", .{ f.id, f.name });
            try self.endObject();
        }

        self.page_tree_id = try self.createIRefID();
        self.current_page = try self.startPage(page_width, page_height);
    }

    /// Calling endDocument() "finishes" the document.
    /// After that, any changes to the pdf document will not generate a valid pdf file.
    pub fn endDocument(self: *PDFWriter) !void {
        try self.endPage(self.current_page, self.page_tree_id);
        try self.writePageTree(self.page_ids.items, self.page_tree_id);
        const catalog_id = try self.writeCatalog(self.page_tree_id);
        const xref_offset = try self.writeXRef();
        try self.writeTrailer(xref_offset, catalog_id);
    }

    pub fn newPage(self: *PDFWriter, page_width: u16, page_height: u16) !void {
        try self.endPage(self.current_page, self.page_tree_id);
        self.current_page = try self.startPage(page_width, page_height);
    }

    pub fn putText(self: *PDFWriter, text: []const u8, font_id: u16, font_size: u16, x: i32, y: i32) !void {
        try self.appendFormatted("BT\n/F{d} {d} Tf\n{d} {d} Td\n(", .{ font_id, font_size, x, y });
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

    /// Get page number of the currently active page starting at 1.
    /// Carefull when calling this after endDocument()
    pub fn getCurrentPageNumber(self: *PDFWriter) usize {
        // number of pages finished plus current one
        return self.page_ids.items.len + 1;
    }

    fn writeCatalog(self: *PDFWriter, page_tree_id: usize) !usize {
        const catalog_id = try self.startObject();
        try self.appendFormatted("<<\n/Type /Catalog\n/Pages {d} 0 R\n>>\n", .{page_tree_id});
        try self.endObject();
        return catalog_id;
    }

    fn startPage(self: *PDFWriter, page_width: u16, page_height: u16) !PageDef {
        const page_id = try self.startObject();
        const stream = try self.startStream();
        return PageDef{ .stream = stream, .page_id = page_id, .width = page_width, .height = page_height };
    }

    fn endPage(self: *PDFWriter, page: PageDef, page_tree_id: usize) !void {
        try self.endStream(page.stream);
        try self.endObject();

        // TODO: automate fonts ids..
        const page_id = try self.startObject();
        const page_string =
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
        try self.appendFormatted(page_string, .{ page_tree_id, self.fonts[0], self.fonts[1], self.fonts[2], page.width, page.height, page.page_id });
        try self.endObject();
        try self.page_ids.append(page_id);
    }

    fn writePageTree(self: *PDFWriter, page_ids: []const usize, page_tree_id: usize) !void {
        try self.startObjectWithId(page_tree_id);
        try self.append("<<\n/Type /Pages\n/Kids [\n");
        for (page_ids) |pageId| {
            try self.appendFormatted("   {d} 0 R\n", .{pageId});
        }
        try self.appendFormatted("]\n/Count {d}\n>>\n", .{page_ids.len});
        try self.endObject();
    }

    fn writeXRef(self: *PDFWriter) !usize {
        const xref_offset = self.getEncodedBytes();
        try self.buffer.appendSlice("xref\n");
        const N = self.i_ref_offsets.items.len;
        try self.appendFormatted("{d} {d}\n", .{ 0, N });

        // objectId 0 is invalid.. but must be in xref..  the pdf spec is WEIRD!
        try self.append("0000000000 65535 f \n");
        var i: u32 = 1;
        while (i < N) : (i += 1) {
            try self.appendFormatted("{d:0>10} 00000 n \n", .{self.i_ref_offsets.items[i]});
        }
        return xref_offset;
    }

    fn writeTrailer(self: *PDFWriter, xrefOffset: usize, catalogId: usize) !void {
        const trailer_string =
            \\trailer
            \\<<
            \\/Size {d}
            \\/Root {d} 0 R
            \\>>
            \\startxref
            \\{d}
            \\%%EOF
        ;
        try self.appendFormatted(trailer_string, .{ self.i_ref_offsets.items.len, catalogId, xrefOffset });
    }

    // pdf-specific utility functions ========================================================================

    fn startStream(self: *PDFWriter) !StreamDef {
        try self.append("<< /Length ");
        const length_start = self.getEncodedBytes();
        try self.append("          "); // insert rendered length here; avoids move

        try self.append(" >>\nstream\r\n"); // needs \r or \r\n by spec
        const stream_start = self.getEncodedBytes();

        return StreamDef{ .length_start = length_start, .stream_start = stream_start };
    }

    fn endStream(self: *PDFWriter, stream: StreamDef) !void {
        const stream_end = self.getEncodedBytes();
        try self.replaceFormatted(32, stream.length_start, "{d}", .{stream_end - stream.stream_start});
        try self.append("endstream\n");
    }

    fn startObject(self: *PDFWriter) !usize {
        const i_ref_id = try self.createIRefID();
        try self.appendFormatted("{d} 0 obj\n", .{i_ref_id});
        return i_ref_id;
    }

    fn startObjectWithId(self: *PDFWriter, iRefId: usize) !void {
        self.i_ref_offsets.items[iRefId] = self.getEncodedBytes();
        try self.appendFormatted("{d} 0 obj\n", .{iRefId});
    }

    fn endObject(self: *PDFWriter) !void {
        try self.append("endobj\n");
    }

    fn getEncodedBytes(self: *const PDFWriter) usize {
        return self.buffer.items.len;
    }

    fn createIRefID(self: *PDFWriter) !usize {
        const i_ref_id = self.i_ref_offsets.items.len;
        try self.i_ref_offsets.append(self.getEncodedBytes());
        return i_ref_id;
    }

    // pdf-agnostic utility functions ===============================================================

    fn appendFormatted(self: *PDFWriter, comptime format: []const u8, args: anytype) !void {
        try self.buffer.writer().print(format, args);
    }

    fn replaceFormatted(self: *PDFWriter, comptime size: u32, pos: usize, comptime format: []const u8, args: anytype) !void {
        var string_buffer = [_]u8{0} ** size;
        var buffered_writer = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &string_buffer };
        try buffered_writer.writer().print(format, args);
        try self.buffer.replaceRange(pos, buffered_writer.pos, string_buffer[0..buffered_writer.pos]);
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
