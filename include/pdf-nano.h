#pragma once

#include <stdint.h>
#include <unistd.h>

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

/**
 * Get version string
 *
 * @returns version as null-terminated string
 */
const char* getVersion();

/**
 * @param format PageFormat enum
 * @param orientation PageOrientation enum
 *
 * @returns created handle or null pointer on failure
 */
encoder_handle createEncoder(uint32_t format, uint32_t orientation);

/**
 * @param handle a handle created with createEncoder()
 */
void freeEncoder(encoder_handle handle);

/**
 * Finish the current document and return pointer to data.
 * Should only be called once.
 *
 * See also: size().
 *
 * @returns pointer to (binary) PDF data
 */
const unsigned char* render(encoder_handle handle);

/**
 * Get size of rendered data. This is only valid after render() has been called.
 *
 * @returns size in bytes
 */
size_t size(encoder_handle handle);

/**
 * Create a horizontal gap by moving the (virtual) cursor by y.
 *
 * @param y size of gap in dots.
 */
void advanceCursor(encoder_handle handle, uint16_t y);

/**
 * Set font to be used.
 *
 * @param fontId as defined by enum Font
 */
void setFont(encoder_handle handle, uint8_t fontId);

/**
 * Set font size.
 *
 * @param size font size in dots
 */
void setFontSize(encoder_handle handle, uint8_t size);

/**
 * Enables output of page numbers. Should be called before adding content.
 *
 * @param alignment Controlls alignment of page numbers shown
 * @param fontSize Font size of page numbers in dots
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
int32_t showPageNumbers(encoder_handle handle, uint32_t alignment, uint8_t fontSize);

/**
 * Add text at current cursor position.
 *
 * @param text Unicode text to be added. Non latin-1 characters won't be displayed correctly.
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
int32_t addText(encoder_handle handle, const char* text);

/**
 * Add image at current cursor position.
 * 
 * @param raw_jpeg raw bytes of jpeg image (no jpeg2000 or lossless support)
 * @param len length of raw_jpeg array
 * @param width percentage of page content, ignoring borders. 100 is the default and aligns with text.
 * @param alignment controlls alignment of image shown
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
int32_t addImage(encoder_handle handle, const uint8_t* raw_jpeg, uint32_t len, float width, uint32_t alignment);

/**
 * Add horizontal line.
 *
 * @param thickness Line thickness
 */
int32_t addHorizontalLine(encoder_handle handle, float thickness);

/**
 * Start a new table object. Should only use table related calls until calling finishTable().
 *
 * @param colunmWidths pointer to array of table withds in dots
 * @param numColumns number of elements in columnWidths array
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
void startTable(encoder_handle handle, int16_t* columnWidths, uint8_t numColumns);

/**
 * Set table headers at top of the table.
 *
 * @param texts Pointer to array of strings to be rendered
 * @param numColumns Size of texts array
 * @param repeatHeader Controlls if table header should be repeated if table spills onto a new page.
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
int32_t setTableHeaders(encoder_handle handle, const char** texts, uint8_t numColumns, uint8_t repeatHeader);

/**
 * Write a new table row
 *
 * @param texts Pointer to array of strings to be rendered
 * @param numColumns Size of texts array
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
int32_t writeRow(encoder_handle handle, const char** texts, uint8_t numColumns);

/**
 * Finish current table object. Should only be called after startTable().
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
int32_t finishTable(encoder_handle handle);

/**
 * Add a new page and move cursor to top of the new page.
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
int32_t breakPage(encoder_handle handle);

/**
 * @param alignment TextAlignment enum
 */
void setTextAlignment(encoder_handle handle, uint32_t alignment);

/**
 * Set color of any text to be written.
 *
 * @param r Color value in the range [0..1]
 * @param g Color value in the range [0..1]
 * @param b Color value in the range [0..1]
 */
void setFontColor(encoder_handle handle, float r, float g, float b);

/**
 * Set color of table background to be written.
 *
 * @param r Color value in the range [0..1]
 * @param g Color value in the range [0..1]
 * @param b Color value in the range [0..1]
 */
void setFillColor(encoder_handle handle, float r, float g, float b);

/**
 * Set color of any lines drawn, including table grid.
 *
 * @param r Color value in the range [0..1]
 * @param g Color value in the range [0..1]
 * @param b Color value in the range [0..1]
 */
void setStrokeColor(encoder_handle handle, float r, float g, float b);

/**
 * Save document to a file under given name.
 *
 * @param filename name of output file
 *
 * @returns zero on success, error code on failure (see pdf-nano-errors.h)
 */
int32_t saveAs(encoder_handle handle, const char* filename);
