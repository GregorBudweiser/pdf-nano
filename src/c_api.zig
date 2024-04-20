const std = @import("std");
const PDFDocument = @import("./document.zig").PDFDocument;
const PDFNano = @import("./document.zig");
const arch = @import("builtin").target.cpu.arch;

export fn createEncoder(format: u32, orientation: u32) usize {
    if (createAndInit(format, orientation)) |doc| {
        return @intFromPtr(doc);
    } else |_| {
        return 0;
    }
}

/// helper function for createEncoder
fn createAndInit(format: u32, orientation: u32) !*PDFDocument {
    var writer = try std.heap.page_allocator.create(PDFDocument);
    writer.* = PDFDocument.init(std.heap.page_allocator);
    try writer.setupDocument(@enumFromInt(format), @enumFromInt(orientation));
    return writer;
}

export fn freeEncoder(doc: *PDFDocument) void {
    doc.deinit();
    std.heap.page_allocator.destroy(doc);
}

export fn setFontSize(doc: *PDFDocument, size: u8) void {
    doc.setFontSize(size);
}

export fn setFont(doc: *PDFDocument, fontId: u8) void {
    doc.setFontById(fontId);
}

export fn advanceCursor(doc: *PDFDocument, y: u16) void {
    doc.advanceCursor(y);
}

export fn addHorizontalLine(doc: *PDFDocument, thickness: f32) i32 {
    if (doc.hr(thickness)) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn addText(doc: *PDFDocument, text: [*c]const u8) i32 {
    if (doc.addText(std.mem.span(text))) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn render(doc: *PDFDocument) usize {
    if (doc.render()) |slice| {
        return @intCast(@intFromPtr(slice.ptr));
    } else |_| {
        return 0;
    }
}

export fn startTable(doc: *PDFDocument, columns: usize, numColumns: u8) void {
    var cols = @as(*[16]u16, @ptrFromInt(columns));
    doc.startTable(cols[0..numColumns]);
}

export fn writeRow(doc: *PDFDocument, texts: *[16]usize, numColumns: u8) i32 {
    var cols: [16][]u8 = [1][]u8{""} ** 16;
    var i: u8 = 0;
    while (i < numColumns) : (i += 1) {
        cols[i] = std.mem.span(@as([*c]u8, @ptrFromInt(texts[i])));
    }

    if (doc.writeRow(cols[0..numColumns])) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn finishTable(doc: *PDFDocument) i32 {
    if (doc.finishTable()) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn getVersion() usize {
    return @intFromPtr(PDFNano.PDF_NANO_VERSION);
}

export fn breakPage(doc: *PDFDocument) i32 {
    if (doc.breakPage()) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn setTextAlignment(doc: *PDFDocument, alignment: u32) void {
    doc.setTextAlignment(@enumFromInt(alignment));
}

export fn setFontColor(doc: *PDFDocument, r: f32, g: f32, b: f32) void {
    doc.setFontColor(r, g, b);
}

export fn setStrokeColor(doc: *PDFDocument, r: f32, g: f32, b: f32) void {
    doc.setStrokeColor(r, g, b);
}

export fn setFillColor(doc: *PDFDocument, r: f32, g: f32, b: f32) void {
    doc.setFillColor(r, g, b);
}

// allocator needed for wasm
export fn alloc(len: usize) usize {
    if (std.heap.page_allocator.alloc(u64, len + 7 / 8)) |data| {
        return @intFromPtr(data.ptr);
    } else |_| {
        return 0;
    }
}

/// free memory allocated by alloc
export fn free(ptr: usize) void {
    std.heap.page_allocator.free(std.mem.span(@as([*:0]u64, @ptrFromInt(ptr))));
}

/// Calling saveAs() "finishes" the document.
/// After that, any changes to the pdf document will not generate a valid pdf file.
export fn saveAs(doc: *PDFDocument, filename: [*:0]const u8) i32 {
    if (comptime arch.isWasm()) {
        return 0;
    }

    if (doc.save(std.mem.span(filename))) {
        return 0;
    } else |_| {
        return -1;
    }
}
