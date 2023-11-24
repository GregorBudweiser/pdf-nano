#include "../include/pdf-nano.h"
#include <stdio.h>

int main(int argc, char** argv) {
    if (argc <= 1) {
        printf("usage: main.exe <out_filename>\n");
    }

    encoder_handle handle = createEncoder(A4, PORTRAIT);
    setFont(handle, HELVETICA_BOLD);
    setFontSize(handle, 36);
    char title[100];
    sprintf(title, "PDF-Nano v%s\0", getVersion());
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
    addText(handle, "· Lines");
    addText(handle, "· Tables");

    advanceCursor(handle, 15);
    setFont(handle, HELVETICA_BOLD);
    setFontSize(handle, 18);
    addText(handle, "Todo:");

    advanceCursor(handle, 5);
    setFont(handle, HELVETICA_REGULAR);
    setFontSize(handle, 12);
    addText(handle, "· Colors/Background");
    addText(handle, "· Alignment/Justify");
    
    advanceCursor(handle, 15);
    int16_t cols[3] = { 100, 100, 100 };
    const char* texts[3] = { "one ", "two", "three" };
    startTable(handle, cols, 3);
    writeRow(handle, texts, 3);
    finishTable(handle);

    FILE * f = fopen(argv[1], "wb");
    fprintf(f, "%s", render(handle));
    fclose(f);

    freeEncoder(handle);
    return 0;
}
