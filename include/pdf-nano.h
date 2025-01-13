#include <stdint.h>

typedef void* encoder_handle;

enum PageFormat {
    LETTER,
    A4
};

enum PageOrientation {
    PORTRAIT,
    LANDSCAPE
};

enum Font {
    HELVETICA_REGULAR = 1,
    HELVETICA_BOLD,
    COURIER
};

enum TextAlignment {
    LEFT,
    CENTERED,
    RIGHT
};

const char* getVersion();

/**
 * @param format PageFormat enum
 * @param orientation PageOrientation enum
 */
encoder_handle createEncoder(uint32_t format, uint32_t orientation);

void freeEncoder(encoder_handle handle);

const char* render(encoder_handle handle);

void advanceCursor(encoder_handle handle, uint16_t y);
void setFont(encoder_handle handle, uint8_t fontId);
void setFontSize(encoder_handle handle, uint8_t size);

int32_t addText(encoder_handle handle, const char* text);
int32_t addHorizontalLine(encoder_handle handle, float thickness);

void startTable(encoder_handle handle, int16_t* columnWidths, uint8_t numColumns);
int32_t writeRow(encoder_handle handle, const char** texts, uint8_t numColumns);
int32_t finishTable(encoder_handle handle);

int32_t breakPage(encoder_handle handle);

/**
 * @param alignment TextAlignment enum
 */
void setTextAlignment(encoder_handle handle, uint32_t alignment);
void setFontColor(encoder_handle handle, float r, float g, float b);
void setFillColor(encoder_handle handle, float r, float g, float b);
void setStrokeColor(encoder_handle handle, float r, float g, float b);

int32_t saveAs(encoder_handle handle, const char* filename);
