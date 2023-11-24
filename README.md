# Welcome!
**PDF-Nano** is a small(ish) library for generating simple PDF files.

The goal of PDF-Nano is to have a lightweight PDF-library usable from Zig, C and Wasm. 

### Features
The main feature is PDF-Nano's small size. Compiled to wasm, it weighs **less than 64kb**, making it suitable for embedded devices.
To keep the code/binary small only a minimal set of features have been and will be added. Currently the following is supported:
- Text (Latin-1 charset support only)
- Lines
- Fixed layout tables

On the todo list:
- Colors, backgroud fill options
- More text formatting and alignment options

Not on the todo list (due to code size):
- TrueType fonts (if you need a small library you probably don't have space for fonts anyway)
- Pictures such as jpg, png (this would require an image decoder + logic to encode into pdf's raster format)
- Compression

### How to build
PDF-Nano is written in Zig, so you will need the Zig compiler. Then simply compile for your target platform (e.g. wasm):
'''zig build -Doptimize=ReleaseSmall -Dtarget=wasm32-freestanding'''
