const Style = @import("document.zig").Style;
const Color = @import("writer.zig").Color;
const Font = @import("font.zig").Font;
const TextAlignment = @import("layouter.zig").TextAlignment;
const PredefinedFonts = @import("font.zig").PredefinedFonts;

pub const Footer = enum {
    NONE,
    PAGE_NUMBER,
    // TODO: PAGE_NUMBER_AND_TOTAL,
    // TODO: CUSTOM_STRING
};

/// Page properties for a single page in the document
pub const PageProperties = struct {
    width: u16 = 612,
    height: u16 = 792,
    documentBorder: u16 = 72 * 3 / 4, // 3/4 inch
    footer: Footer = .PAGE_NUMBER,
    footerStyle: Style = .{
        .fontSize = 12,
        .font = PredefinedFonts.helveticaRegular,
        .fontColor = Color.BLACK,
        .strokeColor = Color.BLACK,
        .fillColor = Color.WHITE,
        .alignment = TextAlignment.RIGHT,
    },

    pub fn getContentTop(self: *const PageProperties) u16 {
        return self.height - self.documentBorder;
    }

    pub fn getContentBottom(self: *const PageProperties) u16 {
        switch (self.footer) {
            .NONE => {
                return self.documentBorder;
            },
            else => {
                return self.documentBorder + 2 * self.footerStyle.fontSize;
            },
        }
    }

    pub fn getContentWidth(self: *const PageProperties) u16 {
        return self.width - 2 * self.documentBorder;
    }

    pub fn getContentLeft(self: *const PageProperties) u16 {
        return self.documentBorder;
    }

    pub fn getContentRight(self: *const PageProperties) u16 {
        return self.width - self.documentBorder;
    }
};
