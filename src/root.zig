const std = @import("std");

pub const request = @import("request.zig");

pub const auth = @import("auth.zig");

pub const Error = extern struct {
    type: u8 = 0, // always 0
    error_code: u8,
    sequence: u16,
    resource_id: u32,
    minor_opcode: u16,
    major_opcode: u8,
    pad0: u8,
    pad1: [21]u8,
};

pub const ID = enum(Tag) {
    _,

    pub const Tag = u32;
};

pub const Connection = struct {
    stream: std.Io.net.Stream,

    pub const default_display_path = "/tmp/.X11-unix/X0";
    pub const auth_protocol = "MIT-MAGIC-COOKIE-1";

    const Header = extern struct {
        order: u8 = 'l', // 'l' or 'B' aka little or big endian
        pad0: u8 = undefined,
        protocol_major: u16 = 11,
        protocol_minor: u16 = 0,
        auth_name_len: u16 = 0,
        auth_data_len: u16 = 0,
        pad1: u16 = undefined,
    };

    pub fn init(io: std.Io, minimal: std.process.Init.Minimal) !@This() {
        const display_path = default_display_path; // minimal.environ.getPosix("DISPLAY")
        const xauthority = minimal.environ.getPosix("XAUTHORITY");
        return initExplicit(io, display_path, xauthority);
    }

    pub fn initExplicit(io: std.Io, display_path: []const u8, xauthority: ?[]const u8) !@This() {
        const address: std.Io.net.UnixAddress = try .init(display_path);
        const stream = try address.connect(io);

        var stream_writer_buffer: [@sizeOf(Header)]u8 = undefined;
        var stream_writer = stream.writer(io, &stream_writer_buffer);
        const writer = &stream_writer.interface;

        if (xauthority != null) {
            var cookie_buffer: [32]u8 = undefined;
            const cookie_len = try findCookie(io, xauthority.?, &cookie_buffer);
            const cookie = cookie_buffer[0..cookie_len];

            const header: Header = .{
                .auth_name_len = @intCast(auth_protocol.len),
                .auth_data_len = @intCast(cookie.len),
            };

            try writer.writeStruct(header, .little);
            try writer.writeAll(auth_protocol);
            writer.end += (4 - (writer.end % 4)) % 4; // Padding
            try writer.writeAll(cookie[0..cookie_len]);
            writer.end += (4 - (writer.end % 4)) % 4; // Padding
        } else {
            const header: Header = .{};
            try writer.writeStruct(header, .little);
        }

        try writer.flush();

        return .{ .stream = stream };
    }

    pub fn close(self: @This(), io: std.Io) void {
        self.stream.close(io);
    }

    // TODO: clean this mess up
    fn findCookie(io: std.Io, xauthority: []const u8, buf: []u8) !usize {
        var xauth_buffer: [1024]u8 = undefined;
        const dir = try std.Io.Dir.openDirAbsolute(io, std.fs.path.dirname(xauthority).?, .{});
        const xauth_file = try dir.readFile(io, std.fs.path.basename(xauthority), &xauth_buffer);

        var i: usize = 0;
        while (i + 8 <= xauth_file.len) {
            // --- family ---
            if (i + 2 > xauth_file.len) break;
            _ = std.mem.readInt(u16, xauth_file[i..][0..2], .big);
            i += 2;

            // --- address ---
            if (i + 2 > xauth_file.len) break;
            const addr_len = std.mem.readInt(u16, xauth_file[i..][0..2], .big);
            i += 2;
            if (i + addr_len > xauth_file.len) break;
            i += addr_len;

            // --- display ---
            if (i + 2 > xauth_file.len) break;
            const disp_len = std.mem.readInt(u16, xauth_file[i..][0..2], .big);
            i += 2;
            if (i + disp_len > xauth_file.len) break;
            const disp_bytes = xauth_file[i .. i + disp_len];
            _ = disp_bytes;
            i += disp_len;

            // --- auth name ---
            if (i + 2 > xauth_file.len) break;
            const name_len = std.mem.readInt(u16, xauth_file[i..][0..2], .big);
            i += 2;
            if (i + name_len > xauth_file.len) break;
            const name_bytes = xauth_file[i .. i + name_len];
            i += name_len;

            // --- auth data ---
            if (i + 2 > xauth_file.len) break;
            const data_len = std.mem.readInt(u16, xauth_file[i..][0..2], .big);
            i += 2;
            if (i + data_len > xauth_file.len) break;
            const data_bytes = xauth_file[i .. i + data_len];
            i += data_len;

            if (std.mem.eql(u8, name_bytes, auth_protocol)) {
                if (data_len > buf.len) return error.BufferTooSmall;
                @memcpy(buf[0..data_len], data_bytes);
                return data_len;
            }
        }

        return error.CookieNotFound;
    }
};

pub const Setup = struct {
    const Response = extern struct {};
};

// pub const Setup = struct {
//     resource_counter: usize = 0,
//     header: Header,
//     server_info: Info,
//     keyboard_info: KeyboardInfo,
//     /// Will be undefineed after reader.tossBuffered();
//     vendor: []const u8,
//     // later: formats: []PixmapFormat
//     // later: roots: []Screen
//     root_screen: Screen,

//     pub const Header = extern struct {
//         status: u8,
//         pad0: u8,
//         protocol_major: u16,
//         protocol_minor: u16,
//         length: u16, // in 4-byte units
//     };

//     pub const Info = extern struct {
//         release_number: u32,
//         resource_id_base: u32,
//         resource_id_mask: u32,
//         motion_buffer_size: u32,
//     };

//     pub const KeyboardInfo = extern struct {
//         vendor_len: u16,
//         max_request_len: u16,
//         num_roots: u8,
//         num_formats: u8,
//         min_keycode: u8,
//         max_keycode: u8,
//         pad0: u8,
//     };

//     pub fn get(reader: *std.Io.Reader) !@This() {
//         const header = try reader.takeStruct(Header, endian);
//         const server_info = try reader.takeStruct(Info, endian);
//         const keyboard_info = try reader.takeStruct(KeyboardInfo, endian);

//         const vendor_offset = 6;
//         const vendor = (try reader.take(keyboard_info.vendor_len + vendor_offset))[vendor_offset..];
//         try reader.fill((4 - (vendor.len % 4)) % 4);

//         const root_screen = try reader.takeStruct(Screen, endian);

//         return .{
//             .header = header,
//             .server_info = server_info,
//             .keyboard_info = keyboard_info,
//             .vendor = vendor,
//             .root_screen = root_screen,
//         };
//     }

//     pub fn nextId(self: *@This(), comptime T: type) T {
//         if (@typeInfo(T).@"enum".tag_type != ID.Tag) @compileError("invalid type given to nextId");
//         const id = self.server_info.resource_id_base | (self.resource_counter & self.server_info.resource_id_mask);
//         self.resource_counter += 1;
//         return @enumFromInt(id);
//     }
// };

pub const VisualID = enum(ID.Tag) {
    _,
};

pub const Screen = extern struct {
    window: Window, // root
    default_colormap: u32,
    white_pixel: u32,
    black_pixel: u32,
    current_input_masks: u32,
    width_in_pixels: u16,
    height_in_pixels: u16,
    mm_width: u16,
    mm_height: u16,
    min_installed_maps: u16,
    max_installed_maps: u16,
    root_visual_id: VisualID,
    backing_stores: u8,
    save_unders: u8,
    root_depth: u8,
    num_depths: u8,
};

pub const Window = enum(ID.Tag) {
    _,

    pub const EventMask = packed struct(u32) {
        key_press: bool = false,
        key_release: bool = false,
        button_press: bool = false,
        button_release: bool = false,
        enter_window: bool = false,
        leave_window: bool = false,
        pointer_motion: bool = false,
        pointer_motion_hint: bool = false,
        button_1_motion: bool = false,
        button_2_motion: bool = false,
        button_3_motion: bool = false,
        button_4_motion: bool = false,
        button_5_motion: bool = false,
        button_motion: bool = false,
        keymap_state: bool = false,
        exposure: bool = false,
        visibility_change: bool = false,
        structure_notify: bool = false,
        resize_redirect: bool = false,
        substructure_notify: bool = false,
        substructure_redirect: bool = false,
        focus_change: bool = false,
        property_change: bool = false,
        colormap_change: bool = false,
        owner_grab_button: bool = false,
        pad0: u7 = 0,
    };

    pub fn create(
        window: @This(),
        writer: *std.Io.Writer,
        depth: u8, // 0 = copy from parent
        parent: Window,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        border_width: u16,
        class: request.window.Create.Class,
        visual: VisualID,
        value_mask: request.window.Create.ValueMask,
        value_list: []const EventMask,
    ) !void {
        const create_window: request.window.Create = .{
            .depth = depth,
            .window = window,
            .parent = parent,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .border_width = border_width,
            .class = class,
            .visual = visual,
            .value_mask = value_mask,
        };

        try writer.writeStruct(create_window, .little);
        try writer.writeStruct(value_list, .little);
    }

    pub fn destroy(self: @This(), writer: *std.Io.Writer) void {
        const req: request.window.Destroy = .{
            .window = self,
        };
        writer.writeStruct(req, .little) catch unreachable;
        writer.flush() catch unreachable;
    }

    pub fn map(self: @This(), writer: *std.Io.Writer) !void {
        const req: request.window.Map = .{
            .window = self,
        };
        try writer.writeStruct(req, .little);
        try writer.flush();
    }
};

pub const Event = extern struct {
    type: Type,
    event: extern union {
        key: Key,
        expose: Expose,
    },
    // add others here

    pub const Header = packed struct {
        type: u8, // Event type, e.g., KeyPress = 2
        pad0: u8 = undefined,
        sequence: u16, // sequence number from X server
    };

    pub const Type = enum(u8) {
        key_press = 2,
        key_release = 3,
        button_press = 4,
        button_release = 5,
        motion_notify = 6,
        enter_notify = 7,
        leave_notify = 8,
        focus_in = 9,
        focus_out = 10,
        keymap_notify = 11,
        expose = 12,
        graphics_expose = 13,
        no_expose = 14,
        visibility_notify = 15,
        create_notify = 16,
        destroy_notify = 17,
        unmap_notify = 18,
        map_notify = 19,
        map_request = 20,
        reparent_notify = 21,
        configure_notify = 22,
        configure_request = 23,
        gravity_notify = 24,
        resize_request = 25,
        circulate_notify = 26,
        circulate_request = 27,
        property_notify = 28,
        selection_clear = 29,
        selection_request = 30,
        selection_notify = 31,
        colormap_notify = 32,
        client_message = 33,
        mapping_notify = 34,
        // 35–127 are unused/reserved
        _,
    };

    pub const GravityNotify = packed struct {
        header: Event.Header,
        event: Window,
        window: Window,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        x_root: i16,
        y_root: i16,
        pad0: u16, // to make 32 bytes
    };

    pub const Key = extern struct {
        header: Header,
        window: u32,
        root: u32,
        subwindow: u32,
        time: u32,
        x: i16,
        y: i16,
        x_root: i16,
        y_root: i16,
        state: u16,
        keycode: u8,
        same_screen: u8,
    };

    pub const Expose = extern struct {
        header: Header,
        window: Window,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        count: u16,
        pad0: u16,
    };
};
