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
    document_border: u16 = 72 * 3 / 4, // 3/4 inch
    footer: Footer = .PAGE_NUMBER,
    footer_style: Style = .{
        .font_size = 12,
        .font = PredefinedFonts.helvetica_regular,
        .font_color = Color.BLACK,
        .stroke_color = Color.BLACK,
        .fill_color = Color.WHITE,
        .alignment = TextAlignment.RIGHT,
    },

    pub fn getContentTop(self: *const PageProperties) u16 {
        return self.height - self.document_border;
    }

    pub fn getContentBottom(self: *const PageProperties) u16 {
        switch (self.footer) {
            .NONE => {
                return self.document_border;
            },
            else => {
                return self.document_border + 2 * self.footer_style.font_size;
            },
        }
    }

    pub fn getContentWidth(self: *const PageProperties) u16 {
        return self.width - 2 * self.document_border;
    }

    pub fn getContentLeft(self: *const PageProperties) u16 {
        return self.document_border;
    }

    pub fn getContentRight(self: *const PageProperties) u16 {
        return self.width - self.document_border;
    }
};
