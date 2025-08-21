# Welcome!
**PDF-Nano** is a small(ish) library for generating simple PDF files.

The goal of PDF-Nano is to have a lightweight PDF-library usable from Zig, C and Wasm. 

### Features
The main feature is PDF-Nano's small size. Compiled to wasm, it weighs **less than 64kb**, making it suitable for embedded devices.
To keep the code/binary small only a minimal set of features have been and will be added. Currently the following is supported:
- Text (Latin-1 charset support only)
- Lines
- Tables (fixed layout)
- Colors (font, storke, fill/table background)
- Alignment (left, center, right)
- Optionally repeat table header on new page

Nice to have at some point:
- Unify/improve handling of text/table styles
- Text justify

Not on the todo list (due to code size):
- TrueType fonts (if you need a small library you probably don't have space for fonts anyway)
- Pictures such as jpg, png (this would require an image decoder + logic to encode into pdf's raster format)
- Compression

### How to build
PDF-Nano is written in Zig, so you will need the Zig compiler. Then simply compile for your target platform (e.g. wasm):

    zig build -Doptimize=ReleaseSmall -Dtarget=wasm32-freestanding

### Build compatibility
| PDF-Nano     | Zig                        |
|--------------|----------------------------|
| **v0.7.0**   | **v0.15.x**                |
| v0.6.0       | v0.14.x                    |
| v0.5.0       | v0.13.0                    |
| v0.4.0       | v0.13.0                    |
| v0.3.0       | v0.12.0-dev.3291+17bad9f88 |
| v0.2.0       | v0.11.0                    |
| v0.1.0       | v0.11.0                    |

### Usage
PDF-Nano provides a text-editor like interface, meaning it handles layouting/positioning for you.
See an [example here](examples/native/main.c).

```c
#include <pdf-nano.h>

int main(int argc, char** argv) {
    encoder_handle handle = createEncoder(A4, PORTRAIT);
    addText(handle, "Hello world!");
    saveAs(handle, "hello.pdf");
    freeEncoder(handle);
    return 0;
}
```

There is also a [typescript wrapper](examples/web/pdf-nano.ts).
