
import { TextAlignment, Font, PDFDocument } from './pdf-nano';

/**
 * Example for creating a pdf file showing all of the features of pdf-nano
 *
 * @param wasmFile the wasm file loaded via some request (pdf-nano.wasm)
 * @returns example pdf file as blob which could be saved with saveAs() or similar
 */
export async function createExampleFile(wasmFile: Blob): Promise<Blob> {
    await PDFDocument.loadWasm(wasmFile);
    const doc = new PDFDocument();
    doc.showPageNumbers(TextAlignment.CENTERED, 10);

    doc.setFont(Font.ARIAL_BOLD);
    doc.setFontSize(36);
    doc.addText("PDF-Nano v" + doc.getVersion());
    doc.addHorizontalLine(1.5);

    doc.advanceCursor(15);
    doc.setFont(Font.ARIAL_REGULAR);
    doc.setFontSize(12);
    doc.addText("PDF-Nano is a tiny pdf library for projects where storage space is limited. The goal is to support as many features as possible while staying below ~64kB.");

    doc.advanceCursor(15);
    doc.setFont(Font.ARIAL_BOLD);
    doc.setFontSize(18);
    doc.addText("Done:");

    doc.advanceCursor(5);
    doc.setFont(Font.COURIER);
    doc.setFontSize(12);
    doc.addText("· Basic Fonts/Text/Pages");
    doc.setFont(Font.ARIAL_REGULAR);
    doc.addText("· Umlaut: äöü èàé");
    doc.addText("· Lines/Tables");
    doc.setFontColor(0.8, 0.2, 0.1);
    doc.addText("· Colors");
    doc.setFontColor(0, 0, 0);
    doc.setTextAlignment(TextAlignment.CENTERED);
    doc.addText("· Centered");
    doc.setTextAlignment(TextAlignment.RIGHT);
    doc.addText("· Right Align");
    doc.setTextAlignment(TextAlignment.LEFT);

    doc.advanceCursor(15);
    doc.setFont(Font.ARIAL_BOLD);
    doc.setFontSize(18);
    doc.addText("Todo:");

    doc.advanceCursor(5);
    doc.setFont(Font.ARIAL_REGULAR);
    doc.setFontSize(12);
    doc.addText("· Justify Text");
    
    doc.advanceCursor(15);
    doc.startTable([100, 100, 286]);

    doc.setTableHeader(["Table..", "..header..", "..with backgound color.."], true);

    for (var i = 0; i < 20; i++) {
      var value = ((i&1) == 0) ? 1 : 0.95;
      doc.setFillColor(value, value, value);
      doc.addTableRow(["One..", "Two..", "Three!"]);
    }

    doc.finishTable();

    doc.breakPage();
    doc.addText("Next page!");

    const data = doc.render();
    doc.destroy();
    return new Blob([data]);
}