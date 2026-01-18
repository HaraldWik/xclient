const std = @import("std");

pub const request = struct {
    pub const Opcode = enum(u8) {
        create_window = 1,
        change_window_attributes = 2,
        get_window_attributes = 3,
        destroy_window = 4,
        destroy_subwindows = 5,
        change_save_set = 6,
        reparent_window = 7,
        map_window = 8,
        map_subwindows = 9,
        unmap_window = 10,
        unmap_subwindows = 11,
        configure_window = 12,
        circulate_window = 13,
        get_geometry = 14,
        query_tree = 15,
        intern_atom = 16,
        get_atom_name = 17,
        change_property = 18,
        delete_property = 19,
        get_property = 20,
        list_properties = 21,
        set_selection_owner = 22,
        get_selection_owner = 23,
        convert_selection = 24,
        send_event = 25,
        grab_pointer = 26,
        ungrab_pointer = 27,
        grab_button = 28,
        ungrab_button = 29,
        change_active_pointer_grab = 30,
        grab_keyboard = 31,
        ungrab_keyboard = 32,
        grab_key = 33,
        ungrab_key = 34,
        allow_events = 35,
        grab_server = 36,
        ungrab_server = 37,
        query_pointer = 38,
        get_motion_events = 39,
        translate_coords = 40,
        warp_pointer = 41,
        set_input_focus = 42,
        get_input_focus = 43,
        query_keymap = 44,
        open_font = 45,
        close_font = 46,
        query_font = 47,
        query_text_extents = 48,
        list_fonts = 49,
        list_fonts_with_info = 50,
        set_font_path = 51,
        get_font_path = 52,
        create_pixmap = 53,
        free_pixmap = 54,
        create_gc = 55,
        change_gc = 56,
        copy_gc = 57,
        set_dashes = 58,
        set_clip_rectangles = 59,
        free_gc = 60,
        clear_area = 61,
        copy_area = 62,
        copy_plane = 63,
        poly_point = 64,
        poly_line = 65,
        poly_segment = 66,
        poly_rectangle = 67,
        poly_arc = 68,
        fill_poly = 69,
        poly_fill_rectangle = 70,
        poly_fill_arc = 71,
        put_image = 72,
        get_image = 73,
        poly_text8 = 74,
        poly_text16 = 75,
        image_text8 = 76,
        image_text16 = 77,
        create_colormap = 78,
        free_colormap = 79,
        copy_colormap_and_free = 80,
        install_colormap = 81,
        uninstall_colormap = 82,
        list_installed_colormaps = 83,
        alloc_color = 84,
        alloc_named_color = 85,
        alloc_color_cells = 86,
        alloc_color_planes = 87,
        free_colors = 88,
        store_colors = 89,
        store_named_color = 90,
        query_colors = 91,
        lookup_color = 92,
        create_cursor = 93,
        create_glyph_cursor = 94,
        free_cursor = 95,
        recolor_cursor = 96,
        query_best_size = 97,
        query_extension = 98,
        list_extensions = 99,
        change_keyboard_mapping = 100,
        get_keyboard_mapping = 101,
        change_keyboard_control = 102,
        get_keyboard_control = 103,
        bell = 104,
        change_pointer_control = 105,
        get_pointer_control = 106,
        set_screen_saver = 107,
        get_screen_saver = 108,
        change_hosts = 109,
        list_hosts = 110,
        set_access_control = 111,
        set_close_down_mode = 112,
        kill_client = 113,
        rotate_properties = 114,
        force_screen_saver = 115,
        set_pointer_mapping = 116,
        get_pointer_mapping = 117,
        set_modifier_mapping = 118,
        get_modifier_mapping = 119,
    };

    pub const Header = extern struct {
        opcode: Opcode, // X11 request code
        detail: u8 = 0, // usually 0
        length: u16, // total length of request in 4-byte units

        pub fn getLength(comptime T: type) comptime_int {
            return @sizeOf(@This()) - @sizeOf(T);
        }
    };
};

pub const Atom = enum(u32) {
    protocols = 0x1234,
    delete_window = 0x1235,
    _,
};

pub const Connection = struct {
    io: std.Io,
    stream: std.Io.net.Stream,

    pub const default_display_path = "/tmp/.X11-unix/X0";
    pub const auth_protocol = "MIT-MAGIC-COOKIE-1";

    pub const Header = extern struct {
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

        return .{ .io = io, .stream = stream };
    }

    pub fn close(self: @This()) void {
        self.stream.close(self.io);
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

pub const ID = enum(Tag) {
    _,
    pub const Tag = u32;
};

pub const VisualID = enum(ID.Tag) {
    _,
};

pub const Setup = struct {
    resource_count: u32 = 0,
    resource_base: u32,
    resource_mask: u32,
    root: Screen,

    pub const StatusHeader = extern struct {
        status: Status,
        pad0: u8,
        protocol_major: u16,
        protocol_minor: u16,
        length: u16, // in 4-byte units

        pub const Status = enum(u8) {
            success = 1,
            failure = 0,
            authenticate = 2,
        };
    };

    pub const ServerInfo = extern struct {
        resource_base: u32,
        resource_mask: u32,
        pad0: u32 = undefined,
        vendor_len: u16,
        pad1: [3]u8 = undefined,
        num_formats: u8,
    };

    pub const KeyboardInfo = extern struct {
        vendor_len: u16,
        max_request_len: u16,
        num_roots: u8,
        num_formats: u8,
        min_keycode: u8,
        max_keycode: u8,
        pad0: u8,
    };

    pub fn get(reader: *std.Io.Reader) !@This() {
        // _ = try connection.stream.socket.receive(connection.io, reader.buffer[0..8]);
        try reader.fillMore();
        defer reader.tossBuffered();
        const header = try reader.takeStruct(StatusHeader, .little);

        switch (header.status) {
            .success => {},
            .failure => return error.Failure,
            .authenticate => {
                std.log.info("Authentication required. Run: xhost +local:", .{});
                return error.Authentication;
            },
        }

        const server_info: ServerInfo = .{
            .resource_base = std.mem.readInt(u32, reader.buffer[12..16], .little),
            .resource_mask = std.mem.readInt(u32, reader.buffer[16..20], .little),
            .vendor_len = std.mem.readInt(u16, reader.buffer[24..26], .little),
            .num_formats = reader.buffer[29],
        };
        // reader.toss(4);
        // const server_info = try reader.takeStruct(ServerInfo, .little);

        const vendor_pad = (4 - (server_info.vendor_len % 4)) % 4;
        const formats_len = 8 * server_info.num_formats;
        const screens_offset = 40 + server_info.vendor_len + vendor_pad + formats_len;
        reader.seek += screens_offset;
        // const root = try reader.takeStruct(Screen, .little);

        const root_window: Window = @enumFromInt(std.mem.readInt(u32, reader.buffer[screens_offset .. screens_offset + 4][0..4], .little));
        const root_visual: VisualID = @enumFromInt(std.mem.readInt(u32, reader.buffer[screens_offset + 32 .. screens_offset + 36][0..4], .little));
        var root: Screen = std.mem.zeroes(Screen);
        root.window = root_window;
        root.visual_id = root_visual;

        return .{
            .resource_base = server_info.resource_base,
            .resource_mask = server_info.resource_mask,
            .root = root,
        };
    }

    // pub fn get(reader: *std.Io.Reader) !@This() {
    //     const header = try reader.takeStruct(StatusHeader, .little);
    //     const server_info = try reader.takeStruct(Info, .little);
    //     const keyboard_info = try reader.takeStruct(KeyboardInfo, .little);

    //     const vendor_offset = 6;
    //     const vendor = (try reader.take(keyboard_info.vendor_len + vendor_offset))[vendor_offset..];
    //     try reader.fill((4 - (vendor.len % 4)) % 4);

    //     const root_screen = try reader.takeStruct(Screen, .little);

    //     return .{
    //         .header = header,
    //         .server_info = server_info,
    //         .keyboard_info = keyboard_info,
    //         .vendor = vendor,
    //         .root_screen = root_screen,
    //     };
    // }

    pub fn nextId(self: *@This(), comptime T: type) T {
        if (@typeInfo(T).@"enum".tag_type != ID.Tag) @compileError("invalid type given to nextId");
        const id = self.resource_base | (self.resource_count & self.resource_mask);
        self.resource_count += 1;
        return @enumFromInt(id);
    }
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
    visual_id: VisualID,
    backing_stores: u8,
    save_unders: u8,
    root_depth: u8,
    num_depths: u8,
};

pub const Window = enum(ID.Tag) {
    _,

    pub const Create = extern struct {
        header: request.Header = .{
            .opcode = .create_window,
            .length = 0, // EXAMPLE: .length = 8 + flag_count;
        },
        window: Window,
        parent: Window, // root window or parent
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        border_width: u16,
        class: Class = .input_output,
        visual_id: VisualID, // usually copied from parent
        value_mask: ValueMask,

        pub const Class = enum(u16) {
            copy_from_parent = 0,
            input_output = 1,
            input_only = 2,
        };

        pub const ValueMask = packed struct(u32) {
            background_pixmap: bool = false,
            background_pixel: bool = false,
            border_pixmap: bool = false,
            border_pixel: bool = false,
            bit_gravity: bool = false,
            win_gravity: bool = false,
            backing_store: bool = false,
            backing_planes: bool = false,
            backing_pixel: bool = false,
            override_redirect: bool = false,
            save_under: bool = false,
            event_mask: bool = false,
            do_not_propagate_mask: bool = false,
            colormap: bool = false,
            cursor: bool = false,

            pad0: u17 = 0, // bits 15–31
        };
    };

    pub const Destroy = extern struct {
        header: request.Header = .{
            .opcode = .destroy_window,
            .length = 2,
        },
        window: Window,
    };

    pub const Map = extern struct {
        header: request.Header = .{
            .opcode = .map_window,
            .length = 2,
        },
        window: Window,
    };

    pub const Config = struct {
        parent: Window,
        x: i16 = 0,
        y: i16 = 0,
        width: u16,
        height: u16,
        border_width: u16,
        visual_id: VisualID,
    };

    pub fn create(self: @This(), writer: *std.Io.Writer, config: Config) !void {
        const flag_count = 2;
        const request_length: u16 = 8 + flag_count;

        const req: Create = .{
            .header = .{
                .opcode = .create_window,
                .length = request_length,
            },
            .window = self,
            .parent = config.parent,
            .x = config.x,
            .y = config.y,
            .width = config.width,
            .height = config.height,
            .border_width = config.border_width,
            .visual_id = config.visual_id,
            .value_mask = .{ .event_mask = true, .background_pixel = true },
        };

        try writer.writeStruct(req, .little);

        try writer.writeInt(u32, 0xff2F768A, .little);
        try writer.writeInt(u32, @bitCast(Event.Mask{ .exposure = true, .key_press = true, .key_release = true, .focus_change = true, .button_press = true, .button_release = true }), .little);
    }

    pub fn destroy(self: @This(), writer: *std.Io.Writer) void {
        const req: Destroy = .{
            .window = self,
        };
        writer.writeStruct(req, .little) catch unreachable;
        writer.flush() catch unreachable;
    }

    pub fn map(self: @This(), writer: *std.Io.Writer) !void {
        const req: Map = .{ .window = self };
        try writer.writeStruct(req, .little);
    }
};

pub const Event = union(Tag) {
    close: void,
    key_press: Key,
    key_release: Key,
    button_press: Button,
    button_release: Button,
    motion_notify: MotionNotify,
    enter_notify: EnterLeaveNotify,
    leave_notify: EnterLeaveNotify,
    focus_in: FocusInOut,
    focus_out: FocusInOut,
    keymap_notify: KeymapNotify,
    expose: Expose,
    graphics_expose: GraphicsExpose,
    no_expose: NoExpose,
    visibility_notify: VisibilityNotify,
    create_notify: CreateNotify,
    destroy_notify: DestroyNotify,
    unmap_notify: UnmapNotify,
    map_notify: MapNotify,
    map_request: MapRequest,
    reparent_notify: ReparentNotify,
    configure_notify: ConfigureNotify,
    configure_request: ConfigureRequest,
    gravity_notify: GravityNotify,
    resize_request: ResizeRequest,
    circulate_notify: CirculateNotify,
    circulate_request: CirculateRequest,
    property_notify: PropertyNotify,
    selection_clear: SelectionClear,
    selection_request: SelectionRequest,
    selection_notify: SelectionNotify,
    colormap_notify: ColormapNotify,
    client_message: ClientMessage,
    mapping_notify: MappingNotify,
    non_standard: NonStandard,

    pub const Tag = enum(u8) {
        close = 255,
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
        non_standard,
        // 35–127 are unused/reserved
        _,
    };

    pub const ModifierState = packed struct(u16) {
        shift: bool = false, // ShiftMask
        lock: bool = false, // LockMask (Caps)
        control: bool = false, // ControlMask
        mod1: bool = false, // Alt
        mod2: bool = false, // Num Lock (usually)
        mod3: bool = false,
        mod4: bool = false, // Super / Meta
        mod5: bool = false,
        button1: bool = false,
        button2: bool = false,
        button3: bool = false,
        button4: bool = false,
        button5: bool = false,
        pad0: u3 = 0,
    };

    /// The keycode is in the header.detail field
    pub const Key = extern struct {
        header: request.Header,
        time_ms: u32,
        root: Window,
        event: Window,
        child: Window,
        root_x: i16,
        root_y: i16,
        event_x: i16,
        event_y: i16,
        state: ModifierState,
        keycode: u8, // detail
        is_same_screen: bool,
    };

    pub const Button = extern struct {
        header: request.Header,
        window: Window,
        root: Window,
        child: Window,
        time_ms: u32,
        x: i16,
        y: i16,
        x_root: i16,
        y_root: i16,
        state: ModifierState,
        button: Type,
        is_same_screen: u8,

        pub const Type = enum(u8) {
            left = 1,
            middle = 2,
            right = 3,
            scroll_up = 4,
            scroll_down = 5,
            scroll_left = 6, // (rare)
            scroll_right = 7, // (rare)
            forward = 8, // forward / extra button 1
            backward = 9, // backward / extra button 2
        };
    };

    pub const MotionNotify = extern struct {
        header: request.Header,
        window: Window,
        root: Window,
        child: Window,
        time_ms: u32,
        x: i16,
        y: i16,
        x_root: i16,
        y_root: i16,
        state: ModifierState,
        is_same_screen: bool,
        pad0: u8,
    };

    pub const NotifyMode = enum(u8) {
        normal = 0,
        grab = 1,
        ungrab = 2,
        while_grabbed = 3,
    };

    pub const NotifyDetail = enum(u8) {
        ancestor = 0,
        virtual_ancestor = 1,
        inferiors = 2,
        nonlinear = 3,
        nonlinear_virtual = 4,
        pointer = 5,
        pointer_root = 6,
        none = 7,
    };

    pub const EnterLeaveNotify = extern struct {
        header: request.Header,
        window: Window,
        root: Window,
        child: Window,
        time_ms: u32,
        x: i16,
        y: i16,
        x_root: i16,
        y_root: i16,
        state: ModifierState,
        mode: NotifyMode,
        detail: NotifyDetail,
        is_same_screen: bool,
        focus: u8,
    };

    pub const FocusInOut = extern struct {
        header: request.Header,
        detail: NotifyDetail,
        pad0: [3]u8 = undefined,
        window: Window,
        mode: NotifyMode,
        pad1: [3]u8 = undefined,
    };

    pub const KeymapNotify = extern struct {
        header: request.Header,
        key_vector: [32]u8,
    };

    pub const Expose = extern struct {
        header: request.Header,
        window: Window,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        count: u16,
        pad0: u16,
    };

    pub const GraphicsExpose = extern struct {
        header: request.Header,
        drawable: u32,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        count: u16,
        major_code: u16,
        minor_code: u16,
    };

    pub const NoExpose = extern struct {
        header: request.Header,
        drawable: u32,
        major_code: u16,
        minor_code: u16,
    };

    pub const VisibilityNotify = extern struct {
        header: request.Header,
        window: Window,
        state: State,

        pub const State = enum(u8) {
            unobscured = 0,
            partially_obscured = 1,
            fully_obscured = 2,
        };
    };

    pub const CreateNotify = extern struct {
        header: request.Header,
        parent: Window,
        window: Window,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        border_width: u16,
        override_redirect: bool,
    };

    pub const DestroyNotify = extern struct {
        header: request.Header,
        event: Window,
        window: Window,
    };

    pub const UnmapNotify = extern struct {
        header: request.Header,
        event: Window,
        window: Window,
        from_configure: bool,
    };

    pub const MapNotify = extern struct {
        header: request.Header,
        event: Window,
        window: Window,
        override_redirect: bool,
    };

    pub const MapRequest = extern struct {
        header: request.Header,
        parent: Window,
        window: Window,
    };

    pub const ReparentNotify = extern struct {
        header: request.Header,
        event: Window,
        window: Window,
        parent: Window,
        x: i16,
        y: i16,
        override_redirect: bool,
    };

    pub const ConfigureNotify = extern struct {
        header: request.Header,
        event: Window,
        window: Window,
        above_sibling: Window,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        border_width: u16,
        override_redirect: bool,
    };

    pub const ConfigureRequest = extern struct {
        header: request.Header,
        parent: Window,
        window: Window,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        border_width: u16,
        above_sibling: Window,
        detail: StackMode,
        value_mask: CWValues,

        pub const StackMode = enum(u8) {
            above = 0,
            below = 1,
            top_if = 2,
            bottom_if = 3,
            opposite = 4,
        };

        pub const CWValues = packed struct(u16) {
            x: bool = false,
            y: bool = false,
            width: bool = false,
            height: bool = false,
            border_width: bool = false,
            sibling: bool = false,
            stack_mode: bool = false,
            pad0: u9,
        };
    };

    pub const GravityNotify = extern struct {
        header: request.Header,
        event: Window,
        window: Window,
        x: i16,
        y: i16,
    };

    pub const ResizeRequest = extern struct {
        header: request.Header,
        window: Window,
        width: u16,
        height: u16,
    };

    pub const Place = enum(u8) {
        on_top = 0,
        on_bottom = 1,
    };

    pub const CirculateNotify = extern struct {
        header: request.Header,
        event: Window,
        window: Window,
        place: Place,
    };

    pub const CirculateRequest = extern struct {
        header: request.Header,
        parent: Window,
        window: Window,
        place: Place,
    };

    pub const PropertyNotify = extern struct {
        header: request.Header,
        window: Window,
        atom: Atom,
        time_ms: u32,
        state: State,

        pub const State = enum(u8) {
            new_value = 0,
            deleted = 1,
        };
    };

    pub const SelectionClear = extern struct {
        header: request.Header,
        time_ms: u32,
        owner: Window,
        selection: Atom,
    };

    pub const SelectionRequest = extern struct {
        header: request.Header,
        owner: Window,
        requestor: Window,
        selection: Atom,
        target: Atom,
        property: Atom,
        time_ms: u32,
    };

    pub const SelectionNotify = extern struct {
        header: request.Header,
        requestor: Window,
        selection: Atom,
        target: Atom,
        property: Atom,
        time_ms: u32,
    };

    pub const ColormapNotify = extern struct {
        header: request.Header,
        window: Window,
        colormap: u32,
        new: New,
        state: State,

        pub const State = enum(u8) {
            uninstalled = 0,
            installed = 1,
        };

        pub const New = enum(u8) {
            no = 0,
            yes = 1,
        };
    };

    pub const ClientMessage = extern struct {
        header: request.Header,
        window: Window,
        type: Atom,
        format: Format,
        data: [20]u8, // raw client data

        pub const Format = enum(u8) {
            @"8" = 8,
            @"16" = 16,
            @"32" = 32,
            _,
        };
    };

    pub const MappingNotify = extern struct {
        header: request.Header,
        request: u8, // Mapping modifier
        first_keycode: u8,
        count: u8,
    };

    pub const NonStandard = extern struct {
        header: request.Header,
        data: [32]u8, // arbitrary non-standard event payload
    };

    pub const Mask = packed struct(u32) {
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

    pub fn next(connection: Connection, reader: *std.Io.Reader) !?@This() {
        var pfd = [_]std.posix.pollfd{.{
            .fd = connection.stream.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        const n = try std.posix.poll(&pfd, 1);
        if (n == 0) return null;

        if (pfd[0].revents & std.posix.POLL.IN == 0)
            if ((pfd[0].revents & std.posix.POLL.ERR) != 0) return .close;
        if ((pfd[0].revents & std.posix.POLL.HUP) != 0) return .close;

        reader.tossBuffered();
        reader.fillMore() catch |err| return switch (err) {
            error.EndOfStream => .close,
            else => err,
        };
        const bytes_read = reader.buffered();
        if (bytes_read.len == 0) return null;

        const code = bytes_read[0];
        if (code == 0) return switch (bytes_read[1]) {
            1 => error.Request,
            2 => error.Value,
            3 => error.Window,
            4 => error.Pixmap,
            5 => error.Atom,
            6 => error.Cursor,
            7 => error.Font,
            8 => error.Match,
            9 => error.Drawable,
            10 => error.Access,
            11 => error.Alloc,
            12 => error.Colormap,
            13 => error.GC,
            14 => error.IDChoice,
            15 => error.Name,
            16 => error.Length,
            17 => error.Implementation,
            else => error.Unknown,
        };

        if (code == 1) {
            std.log.info("Unexpected reply", .{});
            return null;
        }

        const event: @This() = switch (@as(Tag, @enumFromInt(code))) {
            .key_press => .{ .key_press = try reader.takeStruct(Key, .little) },
            .key_release => .{ .key_release = try reader.takeStruct(Key, .little) },
            .button_press => .{ .button_press = try reader.takeStruct(Button, .little) },
            .button_release => .{ .button_release = try reader.takeStruct(Button, .little) },
            .motion_notify => .{ .motion_notify = try reader.takeStruct(MotionNotify, .little) },
            .enter_notify => .{ .enter_notify = try reader.takeStruct(EnterLeaveNotify, .little) },
            .leave_notify => .{ .leave_notify = try reader.takeStruct(EnterLeaveNotify, .little) },
            .focus_in => .{ .focus_in = try reader.takeStruct(FocusInOut, .little) },
            .focus_out => .{ .focus_out = try reader.takeStruct(FocusInOut, .little) },
            .keymap_notify => .{ .keymap_notify = try reader.takeStruct(KeymapNotify, .little) },
            .expose => .{ .expose = try reader.takeStruct(Expose, .little) },
            .graphics_expose => .{ .graphics_expose = try reader.takeStruct(GraphicsExpose, .little) },
            .no_expose => .{ .no_expose = try reader.takeStruct(NoExpose, .little) },
            .visibility_notify => .{ .visibility_notify = try reader.takeStruct(VisibilityNotify, .little) },
            .create_notify => .{ .create_notify = try reader.takeStruct(CreateNotify, .little) },
            .destroy_notify => .{ .destroy_notify = try reader.takeStruct(DestroyNotify, .little) },
            .unmap_notify => .{ .unmap_notify = try reader.takeStruct(UnmapNotify, .little) },
            .map_notify => .{ .map_notify = try reader.takeStruct(MapNotify, .little) },
            .map_request => .{ .map_request = try reader.takeStruct(MapRequest, .little) },
            .reparent_notify => .{ .reparent_notify = try reader.takeStruct(ReparentNotify, .little) },
            .configure_notify => .{ .configure_notify = try reader.takeStruct(ConfigureNotify, .little) },
            .configure_request => .{ .configure_request = try reader.takeStruct(ConfigureRequest, .little) },
            .gravity_notify => .{ .gravity_notify = try reader.takeStruct(GravityNotify, .little) },
            .resize_request => .{ .resize_request = try reader.takeStruct(ResizeRequest, .little) },
            .circulate_notify => .{ .circulate_notify = try reader.takeStruct(CirculateNotify, .little) },
            .circulate_request => .{ .circulate_request = try reader.takeStruct(CirculateRequest, .little) },
            .property_notify => .{ .property_notify = try reader.takeStruct(PropertyNotify, .little) },
            .selection_clear => .{ .selection_clear = try reader.takeStruct(SelectionClear, .little) },
            .selection_request => .{ .selection_request = try reader.takeStruct(SelectionRequest, .little) },
            .selection_notify => .{ .selection_notify = try reader.takeStruct(SelectionNotify, .little) },
            .colormap_notify => .{ .colormap_notify = try reader.takeStruct(ColormapNotify, .little) },
            .client_message => .{ .client_message = try reader.takeStruct(ClientMessage, .little) },
            .mapping_notify => .{ .mapping_notify = try reader.takeStruct(MappingNotify, .little) },

            else => .{ .non_standard = try reader.takeStruct(NonStandard, .little) },
        };
        return event;
    }
};
