const std = @import("std");
const PDFDocument = @import("./document.zig").PDFDocument;
const PageFormat = @import("./document.zig").PageFormat;
const PageOrientation = @import("./document.zig").PageOrientation;
const PredefinedFonts = @import("./font.zig").PredefinedFonts;
const TextAlignment = @import("./layouter.zig").TextAlignment;

pub fn main() !void {
    var doc = PDFDocument.init(std.heap.page_allocator);
    defer doc.deinit();

    try doc.setupDocument(PageFormat.A4, PageOrientation.PORTRAIT);
    doc.setFontById(PredefinedFonts.helveticaBold);
    doc.setFontSize(36);
    try doc.addText("PDF-Nano");
    try doc.hr(1.5);

    doc.advanceCursor(15);
    doc.setFontById(PredefinedFonts.helveticaRegular);
    doc.setFontSize(12);
    try doc.addText("PDF-Nano is a tiny pdf library for projects where storage space is limited. The goal is to support as many features as possible while staying below ~64kB.");

    doc.advanceCursor(15);
    doc.setFontById(PredefinedFonts.helveticaBold);
    doc.setFontSize(18);
    try doc.addText("Done:");

    doc.advanceCursor(5);
    doc.setFontById(PredefinedFonts.helveticaRegular);
    doc.setFontSize(12);
    try doc.addText("· Basic Fonts/Text/Pages");
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
    doc.setFontById(PredefinedFonts.helveticaBold);
    doc.setFontSize(18);
    try doc.addText("Todo:");

    doc.advanceCursor(5);
    doc.setFontById(PredefinedFonts.helveticaRegular);
    doc.setFontSize(12);
    try doc.addText("· Justify Text");

    doc.advanceCursor(15);
    const cols = [_]u16{ 100, 100, 286 };
    doc.startTable(&cols);

    const headers = [_][]const u8{ "Table..", "..header..", "..with backgound color.." };
    doc.setFontById(PredefinedFonts.helveticaBold);
    doc.setFillColor(0.9, 0.9, 0.9);
    try doc.writeRow(&headers);

    const texts = [_][]const u8{ "One..", "Two..", "Three!" };
    doc.setFontById(PredefinedFonts.helveticaRegular);
    doc.setFillColor(1, 1, 1);
    try doc.writeRow(&texts);
    try doc.finishTable();

    try doc.breakPage();
    try doc.addText("Second page!");

    try doc.save("hello.pdf");
}
