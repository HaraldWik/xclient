const root = @import("root.zig");

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

    pub fn len(comptime T: type) comptime_int {
        return @sizeOf(T) / 4;
    }
};

pub const window = struct {
    pub const Create = extern struct {
        header: Header = .{
            .opcode = .create_window,
            .length = Header.len(@This()),
        },
        depth: u8, // usually CopyFromParent = 0
        pad0: [3]u8 = undefined, // 3 byte padding for alignment
        window: root.Window, // XID of the window you’re creating
        parent: root.Window, // root window ID
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        border_width: u16,
        class: Class = .input_output, // InputOutput = 1
        visual: root.VisualID, // usually CopyFromParent = 0
        value_mask: ValueMask, // which optional values you’re setting
        // value_list follows if value_mask != 0

        pub const Class = enum(u16) {
            input_output = 1,
            input_only = 2,
        };

        pub const ValueMask = packed struct(u32) {
            background_pixel: bool = false,
            border_pixel: bool = false,
            bit_gravity: bool = false,
            win_gravity: bool = false,
            backing_store: bool = false,
            backing_planes: bool = false,
            backing_pixel: bool = false,
            override_redirect: bool = false,
            colormap: bool = false,
            event_mask: bool = false,
            pad0: u22 = 0,

            pub const empty: @This() = .{};
        };
    };

    pub const Destroy = extern struct {
        header: Header = .{
            .opcode = .destroy_window,
            .length = Header.len(@This()),
        },
        window: root.Window,
    };

    pub const Map = extern struct {
        header: Header = .{
            .opcode = .map_window,
            .length = Header.len(@This()),
        },
        window: root.Window,
    };
};
