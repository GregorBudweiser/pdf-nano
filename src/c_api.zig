const std = @import("std");
const PDFDocument = @import("./document.zig").PDFDocument;
const PDFNano = @import("./document.zig");
const PredefinedFonts = @import("font.zig").PredefinedFonts;
const Jpeg = @import("./jpeg.zig");
const arch = @import("builtin").target.cpu.arch;

// switch allocator depending on target
const allocator: std.mem.Allocator = if (arch.isWasm()) std.heap.wasm_allocator else std.heap.page_allocator;

export fn createEncoder(format: u32, orientation: u32) usize {
    if (createAndInit(format, orientation)) |doc| {
        return @intFromPtr(doc);
    } else |_| {
        return 0;
    }
}

/// helper function for createEncoder
fn createAndInit(format: u32, orientation: u32) !*PDFDocument {
    var writer = try allocator.create(PDFDocument);
    writer.* = PDFDocument.init(allocator);
    try writer.setupDocument(@enumFromInt(format), @enumFromInt(orientation));
    return writer;
}

export fn freeEncoder(doc: *PDFDocument) void {
    doc.deinit();
    allocator.destroy(doc);
}

export fn showPageNumbers(doc: *PDFDocument, alignment: u32, font_size: u8) i32 {
    if (doc.showPageNumbers(@enumFromInt(alignment), font_size)) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn setFontSize(doc: *PDFDocument, font_size: u8) void {
    doc.setFontSize(font_size);
}

export fn setFont(doc: *PDFDocument, fontId: u8) void {
    switch (fontId) {
        2 => {
            doc.setFont(PredefinedFonts.helvetica_bold);
        },
        3 => {
            doc.setFont(PredefinedFonts.courier_regular);
        },
        else => {
            doc.setFont(PredefinedFonts.helvetica_regular);
        },
    }
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

export fn addImage(doc: *PDFDocument, raw_jpeg: [*]const u8, len: u32, width: f32, alignment: u32) i32 {
    if (doc.addImage(raw_jpeg[0..len], width, @enumFromInt(alignment))) {
        return 0;
    } else |err| switch (err) {
        Jpeg.JPEGError.NOT_A_JPEG => {
            return -2;
        },
        Jpeg.JPEGError.TRUNCATED => {
            return -3;
        },
        Jpeg.JPEGError.UNSUPPORTED => {
            return -4;
        },
        else => {
            return -1;
        },
    }
}

export fn render(doc: *PDFDocument) usize {
    if (doc.render()) |slice| {
        return @intCast(@intFromPtr(slice.ptr));
    } else |_| {
        return 0;
    }
}

export fn size(doc: *PDFDocument) usize {
    return doc.size();
}

export fn startTable(doc: *PDFDocument, columns: usize, num_columns: u8) void {
    var cols = @as(*[16]u16, @ptrFromInt(columns));
    doc.startTable(cols[0..num_columns]);
}

export fn writeRow(doc: *PDFDocument, texts: *[16]usize, num_columns: u8) i32 {
    var cols: [16][]u8 = [1][]u8{""} ** 16;
    var i: u8 = 0;
    while (i < num_columns) : (i += 1) {
        cols[i] = std.mem.span(@as([*c]u8, @ptrFromInt(texts[i])));
    }

    if (doc.writeRow(cols[0..num_columns])) {
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

export fn getVersion() [*:0]const u8 {
    return PDFNano.pdf_nano_version;
}

export fn breakPage(doc: *PDFDocument) i32 {
    if (doc.breakPage()) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn setTableHeaders(doc: *PDFDocument, headers: *[16]usize, num_columns: u8, repeat_header: bool) i32 {
    var cols: [16][]u8 = [1][]u8{""} ** 16;
    var i: u8 = 0;
    while (i < num_columns) : (i += 1) {
        cols[i] = std.mem.span(@as([*c]u8, @ptrFromInt(headers[i])));
    }

    if (doc.setTableHeaders(cols[0..num_columns], repeat_header)) {
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
    if (allocator.alloc(u8, len)) |data| {
        return @intFromPtr(data.ptr);
    } else |_| {
        return 0;
    }
}

/// free memory allocated by alloc
export fn free(ptr: usize) void {
    allocator.free(std.mem.span(@as([*:0]u8, @ptrFromInt(ptr))));
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
