const std = @import("std");
const PDFDocument = @import("./document.zig").PDFDocument;
const PDF_NANO_VERSION = @import("./document.zig").PDF_NANO_VERSION;
const PageFormat = @import("./document.zig").PageFormat;
const PageOrientation = @import("./document.zig").PageOrientation;
const PredefinedFonts = @import("./font.zig").PredefinedFonts;
const TextAlignment = @import("./layouter.zig").TextAlignment;

pub fn main() !void {
    var doc = PDFDocument.init(std.heap.page_allocator);
    defer doc.deinit();

    try doc.setupDocument(PageFormat.A4, PageOrientation.PORTRAIT);
    doc.setFont(PredefinedFonts.helveticaBold);
    doc.setFontSize(36);
    try doc.addText("PDF-Nano v" ++ PDF_NANO_VERSION);
    try doc.hr(1.5);

    doc.advanceCursor(15);
    doc.setFont(PredefinedFonts.helveticaRegular);
    doc.setFontSize(12);
    try doc.addText("PDF-Nano is a tiny pdf library for projects where storage space is limited. The goal is to support as many features as possible while staying below ~64kB.");

    doc.advanceCursor(15);
    doc.setFont(PredefinedFonts.helveticaBold);
    doc.setFontSize(18);
    try doc.addText("Done:");

    doc.advanceCursor(5);
    doc.setFont(PredefinedFonts.courierRegular);
    doc.setFontSize(12);
    try doc.addText("· Basic Fonts/Text/Pages");
    doc.setFont(PredefinedFonts.helveticaRegular);
    try doc.addText("· Umlaut: äöü èàé");
    try doc.addText("· Lines/Tables");
    doc.setFontColor(0.8, 0.2, 0.1);
    try doc.addText("· Colors");
    doc.setFontColor(0, 0, 0);
    doc.setTextAlignment(TextAlignment.CENTERED);
    try doc.addText("· Centered");
    doc.setTextAlignment(TextAlignment.RIGHT);
    try doc.addText("· Right Align");
    doc.setTextAlignment(TextAlignment.LEFT);

    doc.advanceCursor(15);
    doc.setFont(PredefinedFonts.helveticaBold);
    doc.setFontSize(18);
    try doc.addText("Todo:");

    doc.advanceCursor(5);
    doc.setFont(PredefinedFonts.helveticaRegular);
    doc.setFontSize(12);
    try doc.addText("· Justify Text");

    doc.advanceCursor(15);
    const cols = [_]u16{ 100, 100, 286 };
    const headers = [_][]const u8{ "Repeating..", "..Table..", "..Header.." };
    const texts = [_][]const u8{ "One..", "Two..", "Three!" };

    doc.startTable(&cols);
    try doc.setTableHeaders(headers[0..], true);
    for (0..20) |i| {
        if ((i & 1) == 0) {
            doc.setFillColor(1, 1, 1);
        } else {
            doc.setFillColor(0.95, 0.95, 0.95);
        }
        try doc.writeRow(&texts);
    }
    try doc.finishTable();

    try doc.breakPage();
    try doc.addText("New page!");

    try doc.save("hello_from_zig.pdf");
}
