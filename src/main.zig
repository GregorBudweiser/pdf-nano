const std = @import("std");
const PDFDocument = @import("./document.zig").PDFDocument;
const PageFormat = @import("./document.zig").PageFormat;
const PageOrientation = @import("./document.zig").PageOrientation;
const PredefinedFonts = @import("./font.zig").PredefinedFonts;

pub fn main() !void {
    var document = PDFDocument.init(std.heap.page_allocator);
    defer document.deinit();

    try document.setupDocument(PageFormat.A4, PageOrientation.PORTRAIT);
    document.setFontById(PredefinedFonts.helveticaBold);
    document.setFontSize(36);
    try document.addText("PDF-Nano");
    try document.hr(1.5);

    document.advanceCursor(15);
    document.setFontById(PredefinedFonts.helveticaRegular);
    document.setFontSize(12);
    try document.addText("PDF-Nano is a tiny pdf library for projects where storage space is limited. The goal is to support as many features as possible while staying below ~64kB.");

    document.advanceCursor(15);
    document.setFontById(PredefinedFonts.helveticaBold);
    document.setFontSize(18);
    try document.addText("Done:");

    document.advanceCursor(5);
    document.setFontById(PredefinedFonts.helveticaRegular);
    document.setFontSize(12);
    try document.addText("· Basic Fonts/Text/Pages");
    try document.addText("· Umlaut: äöü èàé");
    try document.addText("· Lines");
    try document.addText("· Tables");

    document.advanceCursor(15);
    document.setFontById(PredefinedFonts.helveticaBold);
    document.setFontSize(18);
    try document.addText("Todo:");

    document.advanceCursor(5);
    document.setFontById(PredefinedFonts.helveticaRegular);
    document.setFontSize(12);
    try document.addText("· Colors/Background Fill");
    try document.addText("· Right Align/Justify Text");

    document.advanceCursor(5);
    const cols = [_]u16{ 100, 100, 100 };
    document.startTable(&cols);

    const strings = [_][]const u8{ "one", "two", "three" };
    try document.writeRow(&strings);
    try document.finishTable();

    document.advanceCursor(5);
    try document.addText("Test test");

    try document.save("hello.pdf");
}
