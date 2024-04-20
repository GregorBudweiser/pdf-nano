/// Page properties for a single page in the document
pub const PageProperties = struct {
    width: u16 = 612,
    height: u16 = 792,
    documentBorder: u16 = 72 * 3 / 4, // 3/4 inch

    pub fn getContentTop(self: *const PageProperties) u16 {
        return self.height - self.documentBorder;
    }

    pub fn getContentBottom(self: *const PageProperties) u16 {
        return self.documentBorder;
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
