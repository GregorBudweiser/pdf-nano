#include <pdf-nano.h>
#include <stdio.h>

int main(int argc, char** argv) {
    if (argc <= 1) {
        printf("usage: main.exe <out_filename>\n");
        return 0;
    }

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
    setFont(handle, HELVETICA_REGULAR);
    setFontSize(handle, 12);
    addText(handle, "· Basic Fonts/Text/Pages");
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
    int16_t cols[3] = { 100, 100, 280 };
    const char* texts[3] = { "Table..", "..header..", "..with backgound color.." };
    setFont(handle, HELVETICA_BOLD);
    setFillColor(handle, 0.9, 0.9, 0.9);
    startTable(handle, cols, 3);
    writeRow(handle, texts, 3);
    
    const char* texts2[3] = { "One..", "Two..", "Three!" };
    setFont(handle, HELVETICA_REGULAR);
    setFillColor(handle, 1, 1, 1);
    writeRow(handle, texts2, 3);
    finishTable(handle);

    breakPage(handle);
    addText(handle, "Second page!");

    saveAs(handle, argv[1]);

    freeEncoder(handle);
    return 0;
}
