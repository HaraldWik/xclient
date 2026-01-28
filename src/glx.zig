const std = @import("std");
const root = @import("root.zig");

pub const request = struct {
    pub const Opcode = enum(u8) {
        // GLX 1.0
        render = 1,
        render_large = 2,
        create_context = 3,
        destroy_context = 4,
        make_current = 5,
        is_direct = 6,
        query_version = 7,
        wait_gl = 8,
        wait_x = 9,
        copy_context = 10,
        swap_buffers = 11,
        use_x_font = 12,
        create_glx_pixmap = 13,
        get_visual_configs = 14,
        destroy_glx_pixmap = 15,

        // 16, 17 are unused / reserved in GLX 1.0

        // GLX 1.1
        query_extensions_string = 18,

        // GLX 1.2
        query_server_string = 19,
        client_info = 20,

        // GLX 1.3
        get_fb_configs = 21,
        create_pixmap = 22,
        destroy_pixmap = 23,
        create_new_context = 24,
        query_context = 25,
        make_context_current = 26,
        create_pbuffer = 27,
        destroy_pbuffer = 28,
        get_drawable_attributes = 29,
        change_drawable_attributes = 30,

        // GLX 1.4
        create_window = 31,
        destroy_window = 32,

        // ARB extension
        create_context_attribs_arb = 34,

        _,
    };

    pub const Header = extern struct {
        opcode: Opcode,
        detail: u8,
        length: u16,
    };
};

pub fn queryExtension(reader: *std.Io.Reader, writer: *std.Io.Writer, name: []const u8) !bool {
    const req: request.Query = .{ .header = .{ .opcode = .query_extensions_string } };
    writer.writeStruct(req, .little);
    writer.end += (4 - (writer.end % 4)) % 4; // Padding

    _ = reader;

    _ = name;
    return false;
}
