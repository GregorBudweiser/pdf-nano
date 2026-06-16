const std = @import("std");

pub const JPEGError = error{
    NOT_A_JPEG,
    TRUNCATED,
    UNSUPPORTED,
};

pub const JPEGInfo = struct {
    raw: []const u8,
    width: u16,
    height: u16,
    bpp: u8,
    num_channels: u8,

    // pdf-nano specific..
    ref_id: u32,
};

pub const JPEG = struct {
    pub fn parseInfo(raw: []const u8) JPEGError!JPEGInfo {
        var opt: ?[]const u8 = raw;
        while (opt) |remaining| {
            if (remaining.len < 2) {
                return JPEGError.TRUNCATED;
            } else if (remaining[0] != 0xFF) {
                return JPEGError.NOT_A_JPEG;
            }

            switch (remaining[1]) {
                0xC0, 0xC1, 0xC2 => { // start of frame (baseline, exteded, progressive)
                    if (remaining.len < 9) {
                        return JPEGError.TRUNCATED;
                    }
                    var info: JPEGInfo = undefined;
                    info.height = std.mem.readInt(u16, remaining[5..7], .big);
                    info.width = std.mem.readInt(u16, remaining[7..9], .big);
                    info.bpp = remaining[4];
                    info.num_channels = remaining[9];
                    info.raw = raw;
                    info.ref_id = 0;
                    return info;
                },
                0xD9 => { // end of image; if we reach this we did not find a suitable start of frame segment
                    return JPEGError.UNSUPPORTED;
                },
                else => { // irrelevant segment; continue with next
                    opt = next(remaining);
                },
            }
        }
        return JPEGError.TRUNCATED;
    }

    fn next(raw: []const u8) ?[]const u8 {
        if (raw[1] == 0xB8 or raw[1] == 0xD8) { // skip SOI header (does not have length field)
            return raw[2..];
        }
        if (raw.len < 4) {
            return null;
        }

        const len = std.mem.readInt(u16, raw[2..4], .big);
        if (len + 2 > raw.len) {
            return null;
        }
        return raw[2 + len ..];
    }
};

test "parse_empty_data" {
    const content = [_]u8{};
    try std.testing.expectError(JPEGError.TRUNCATED, JPEG.parseInfo(content[0..]));
}

test "parse_invalid_data" {
    const content = [_]u8{ 'p', 'n', 'g' };
    try std.testing.expectError(JPEGError.NOT_A_JPEG, JPEG.parseInfo(content[0..]));
}

test "parse_SOF" {
    const content = [_]u8{
        0xff, 0xd8, 0xff, 0xc2, 0x00, 0x11, 0x08, 0x00,
        0x08, 0x00, 0x08, 0x03, 0x01, 0x11, 0x00, 0x02,
        0x11, 0x01, 0x03, 0x11, 0x01, 0xff, 0xc4, 0x00,
        0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x05, 0xff, 0xc4, 0x00, 0x14, 0x01,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0xff, 0xda, 0x00, 0x0c, 0x03, 0x01, 0x00,
        0x02, 0x10, 0x03, 0x10, 0x00, 0x00, 0x01, 0x40,
        0xff, 0xc4, 0x00, 0x14,
    };
    const dim = try JPEG.parseInfo(content[0..]);
    try std.testing.expectEqual(dim.width, 8);
    try std.testing.expectEqual(dim.height, 8);
}
