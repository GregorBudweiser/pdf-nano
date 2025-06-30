#include <pdf-nano.h>
#include <stdio.h>

int main(int argc, char** argv) {
    encoder_handle handle = createEncoder(A4, PORTRAIT);
    setFont(handle, HELVETICA_BOLD);
    setFontSize(handle, 36);
    char title[100];
    sprintf(title, "PDF-Nano v%s", getVersion());
    addText(handle, title);
    addHorizontalLine(handle, 1.5);

    advanceCursor(handle, 15);
    setFont(handle, HELVETICA_REGULAR);
    setFontSize(handle, 12);
    addText(handle, "PDF-Nano is a tiny pdf library for projects where storage space is limited. The goal is to support as many features as possible while staying below ~64kB.");

    advanceCursor(handle, 15);
    setFont(handle, HELVETICA_BOLD);
    setFontSize(handle, 18);
    addText(handle, "Done:");

    advanceCursor(handle, 5);
    setFont(handle, COURIER);
    setFontSize(handle, 12);
    addText(handle, "· Basic Fonts/Text/Pages");
    setFont(handle, HELVETICA_REGULAR);
    addText(handle, "· Umlaut: äöü èàé");
    addText(handle, "· Lines/Tables");
    setFontColor(handle, 0.8, 0.2, 0.1);
    addText(handle, "· Colors");
    setFontColor(handle, 0, 0, 0);
    setTextAlignment(handle, CENTERED);
    addText(handle, "· Centered");
    setTextAlignment(handle, RIGHT);
    addText(handle, "· Right Align");
    setTextAlignment(handle, LEFT);

    advanceCursor(handle, 15);
    setFont(handle, HELVETICA_BOLD);
    setFontSize(handle, 18);
    addText(handle, "Todo:");

    advanceCursor(handle, 5);
    setFont(handle, HELVETICA_REGULAR);
    setFontSize(handle, 12);
    addText(handle, "· Justify Text");
    
    advanceCursor(handle, 15);
    int16_t cols[3] = { 100, 100, 286 };
    const char* headers[3] = { "Repeating..", "..Table..", "..Header.." };
    const char* texts[3] = { "One..", "Two..", "Three!" };

    startTable(handle, cols, 3);
    setTableHeaders(handle, headers, 3, 1);
    for (size_t i = 0; i < 20; i++) {
        float value = ((i & 1) == 0) ? 1 : 0.95;
        setFillColor(handle, value, value, value);
        writeRow(handle, texts, 3);
    }
    finishTable(handle);

    breakPage(handle);
    addText(handle, "New page!");

    saveAs(handle, "hello_from_c.pdf");

    freeEncoder(handle);
    return 0;
}
