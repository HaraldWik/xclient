const std = @import("std");
const request = @import("request.zig");

pub const Atom = enum(u32) {
    invalid = 0,
    primary = 1,
    secondary = 2,
    arc = 3,
    atom = 4,
    bitmap = 5,
    cardinal = 6,
    colormap = 7,
    cursor = 8,
    cut_buffer0 = 9,
    cut_buffer1 = 10,
    cut_buffer2 = 11,
    cut_buffer3 = 12,
    cut_buffer4 = 13,
    cut_buffer5 = 14,
    cut_buffer6 = 15,
    cut_buffer7 = 16,
    drawable = 17,
    font = 18,
    integer = 19,
    pixmap = 20,
    point = 21,
    rectangle = 22,
    resource_manager = 23,
    rgb_color_map = 24,
    rgb_best_map = 25,
    rgb_blue_map = 26,
    rgb_default_map = 27,
    rgb_gray_map = 28,
    rgb_green_map = 29,
    rgb_red_map = 30,
    string = 31,
    visualid = 32,
    window = 33,
    wm_command = 34,
    wm_hints = 35,
    wm_client_machine = 36,
    wm_icon_name = 37,
    wm_icon_size = 38,
    wm_name = 39,
    wm_normal_hints = 40,
    wm_size_hints = 41,
    wm_zoom_hints = 42,
    min_space = 43,
    norm_space = 44,
    max_space = 45,
    end_space = 46,
    superscript_x = 47,
    superscript_y = 48,
    subscript_x = 49,
    subscript_y = 50,
    underline_position = 51,
    underline_thickness = 52,
    strikeout_ascent = 53,
    strikeout_descent = 54,
    italic_angle = 55,
    x_height = 56,
    quad_width = 57,
    weight = 58,
    point_size = 59,
    resolution = 60,
    copyright = 61,
    notice = 62,
    font_name = 63,
    family_name = 64,
    full_name = 65,
    cap_height = 66,
    wm_class = 67,
    wm_transient_for = 68,
    _,

    pub const GetInternal = extern struct {
        header: request.Header,
        name_len: u16,
        pad0: u16 = undefined,

        pub const Response = extern struct {
            status: Status, // must be 1
            pad0: u8 = undefined,
            sequence: u16,
            length: u32, // always 0
            atom: Atom,
            pad1: [20]u8 = undefined,

            pub const Status = enum(u8) {
                success = 1,
                failure = 0,
                authenticate = 2,
            };
        };
    };

    pub fn getInternal(reader: *std.Io.Reader, writer: *std.Io.Writer, name: []const u8, only_if_exists: bool) !@This() {
        const padded_name_len = (name.len + 3) & ~@as(usize, 3);
        const get_internal: GetInternal = .{
            .header = .{
                .opcode = .intern_atom,
                .detail = @intFromBool(only_if_exists),
                .length = @intCast(8 + padded_name_len),
            },
            .name_len = @intCast(name.len),
        };
        try writer.writeStruct(get_internal, .little);
        try writer.writeAll(name);
        try writer.splatByteAll(0, (4 - (name.len % 4)) % 4);
        try writer.flush();

        const response = try reader.takeStruct(GetInternal.Response, .little);
        std.debug.print("{d}\n", .{response.status});
        if (response.status != .success) return error.ResponseStatus;
        if (response.atom == .invalid) return error.InvalidAtomFound;
        return response.atom;
    }
};
