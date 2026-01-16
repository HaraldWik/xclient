const std = @import("std");
const request = @import("request.zig");

pub const auth = @import("auth.zig");

pub const endian: std.builtin.Endian = .little;

pub const ID = enum(Tag) {
    _,

    pub const Tag = u32;
};

pub const Connection = struct {
    stream: std.Io.net.Stream,

    pub fn open(io: std.Io, minimal: std.process.Init.Minimal) !@This() {
        const display = minimal.environ.getPosix("DISPLAY") orelse return error.NoDisplay;
        var path_buf: [108]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "/tmp/.X11-unix/X{s}\x00", .{display[1..]});
        const address: std.Io.net.UnixAddress = try .init(path);

        const stream = try address.connect(io);

        return .{ .stream = stream };
    }

    pub fn close(self: @This(), io: std.Io) void {
        self.stream.close(io);
    }

    pub fn reader(self: @This(), io: std.Io, buffer: []u8) std.Io.net.Stream.Reader {
        return self.stream.reader(io, buffer);
    }

    pub fn writer(self: @This(), io: std.Io, buffer: []u8) std.Io.net.Stream.Writer {
        return self.stream.writer(io, buffer);
    }
};

pub const Setup = struct {
    resource_counter: usize = 0,
    header: Header,
    server_info: Info,
    keyboard_info: KeyboardInfo,
    /// Will be undefineed after reader.tossBuffered();
    vendor: []const u8,
    // later: formats: []PixmapFormat
    // later: roots: []Screen
    root_screen: Screen,

    pub const Header = extern struct {
        status: u8,
        pad0: u8,
        protocol_major: u16,
        protocol_minor: u16,
        length: u16, // in 4-byte units
    };

    pub const Info = extern struct {
        release_number: u32,
        resource_id_base: u32,
        resource_id_mask: u32,
        motion_buffer_size: u32,
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
        const header = try reader.takeStruct(Header, endian);
        const server_info = try reader.takeStruct(Info, endian);
        const keyboard_info = try reader.takeStruct(KeyboardInfo, endian);

        const vendor_offset = 6;
        const vendor = (try reader.take(keyboard_info.vendor_len + vendor_offset))[vendor_offset..];
        try reader.fill((4 - (vendor.len % 4)) % 4);

        const root_screen = try reader.takeStruct(Screen, endian);

        return .{
            .header = header,
            .server_info = server_info,
            .keyboard_info = keyboard_info,
            .vendor = vendor,
            .root_screen = root_screen,
        };
    }

    pub fn nextId(self: *@This(), comptime T: type) T {
        if (@typeInfo(T).@"enum".tag_type != ID.Tag) @compileError("invalid type given to nextId");
        const id = self.server_info.resource_id_base | (self.resource_counter & self.server_info.resource_id_mask);
        self.resource_counter += 1;
        return @enumFromInt(id);
    }
};

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
        depth: ?u8,
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
            .depth = depth orelse 0,
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

        try writer.writeStruct(create_window, endian);

        for (value_list) |v| {
            try writer.writeStruct(v, endian);
        }
    }

    pub fn destroy(self: @This(), writer: *std.Io.Writer) void {
        const req: request.window.Destroy = .{
            .window = self,
        };
        writer.writeStruct(req, endian) catch unreachable;
    }

    pub fn map(self: @This(), writer: *std.Io.Writer) !void {
        const req: request.window.Map = .{
            .window = self,
        };
        try writer.writeStruct(req, .little);
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
