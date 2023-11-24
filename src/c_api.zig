const std = @import("std");
const PDFDocument = @import("./document.zig").PDFDocument;
const PDFNano = @import("./document.zig");

export fn createEncoder(format: u32, orientation: u32) usize {
    if (createAndInit(format, orientation)) |writer| {
        return @intFromPtr(writer);
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

export fn freeEncoder(handle: usize) void {
    var writer: *PDFDocument = @ptrFromInt(handle);
    writer.deinit();
    std.heap.page_allocator.destroy(writer);
}

export fn setFontSize(handle: usize, size: u8) void {
    var writer: *PDFDocument = @ptrFromInt(handle);
    writer.setFontSize(size);
}

export fn setFont(handle: usize, fontId: u8) void {
    var writer: *PDFDocument = @ptrFromInt(handle);
    writer.setFontById(fontId);
}

export fn advanceCursor(handle: usize, y: u16) void {
    var writer: *PDFDocument = @ptrFromInt(handle);
    writer.advanceCursor(y);
}

export fn addHorizontalLine(handle: usize, thickness: f32) i32 {
    var writer: *PDFDocument = @ptrFromInt(handle);
    if (writer.hr(thickness)) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn addText(handle: usize, text: usize) i32 {
    var writer: *PDFDocument = @ptrFromInt(handle);
    const span = std.mem.span(@as([*c]const u8, @ptrFromInt(text)));
    if (writer.addText(span)) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn render(handle: usize) usize {
    var writer: *PDFDocument = @ptrFromInt(handle);
    if (writer.render()) |slice| {
        return @intCast(@intFromPtr(slice.ptr));
    } else |_| {
        return 0;
    }
}

export fn startTable(handle: usize, columns: usize, numColumns: u8) void {
    var writer: *PDFDocument = @ptrFromInt(handle);
    var cols = @as(*[16]u16, @ptrFromInt(columns));
    writer.startTable(cols[0..numColumns]);
}

export fn writeRow(handle: usize, texts: usize, numColumns: u8) i32 {
    var writer: *PDFDocument = @ptrFromInt(handle);
    var cols: [16][]u8 = [1][]u8{""} ** 16;
    const arrayOfPtr = @as(*[16]usize, @ptrFromInt(texts));

    var i: u8 = 0;
    while (i < numColumns) : (i += 1) {
        cols[i] = std.mem.span(@as([*c]u8, @ptrFromInt(arrayOfPtr[i])));
    }

    if (writer.writeRow(cols[0..numColumns])) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn finishTable(handle: usize) i32 {
    var writer: *PDFDocument = @ptrFromInt(handle);
    if (writer.finishTable()) {
        return 0;
    } else |_| {
        return -1;
    }
}

export fn getVersion() usize {
    return @intFromPtr(PDFNano.PDF_NANO_VERSION);
}

// TODO: Export wasm-only stuff only if target is wasm..

/// allocate memory with alignment of uint64_t
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
