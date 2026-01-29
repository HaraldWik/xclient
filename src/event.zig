const std = @import("std");
const request = @import("request.zig");
const Connection = @import("root.zig").Connection;
const Atom = @import("atom.zig").Atom;
const Window = @import("root.zig").Window;
const Format = @import("root.zig").Format;

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
        header: request.event.Header,
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
        header: request.event.Header,
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
        header: request.event.Header,
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
        header: request.event.Header,
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
        header: request.event.Header,
        detail: NotifyDetail,
        pad0: [3]u8 = undefined,
        window: Window,
        mode: NotifyMode,
        pad1: [3]u8 = undefined,
    };

    pub const KeymapNotify = extern struct {
        response_type: request.Response.Type,
        detail: u8,
        keys: [30]u8,
    };

    pub const Expose = extern struct {
        header: request.event.Header,
        window: Window,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        count: u16,
        pad0: u16,
    };

    pub const GraphicsExpose = extern struct {
        header: request.event.Header,
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
        header: request.event.Header,
        drawable: u32,
        major_code: u16,
        minor_code: u16,
    };

    pub const VisibilityNotify = extern struct {
        header: request.event.Header,
        window: Window,
        state: State,

        pub const State = enum(u8) {
            unobscured = 0,
            partially_obscured = 1,
            fully_obscured = 2,
        };
    };

    pub const CreateNotify = extern struct {
        header: request.event.Header,
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
        header: request.event.Header,
        event: Window,
        window: Window,
    };

    pub const UnmapNotify = extern struct {
        header: request.event.Header,
        event: Window,
        window: Window,
        from_configure: bool,
    };

    pub const MapNotify = extern struct {
        header: request.event.Header,
        event: Window,
        window: Window,
        override_redirect: bool,
    };

    pub const MapRequest = extern struct {
        header: request.event.Header,
        parent: Window,
        window: Window,
    };

    pub const ReparentNotify = extern struct {
        header: request.event.Header,
        event: Window,
        window: Window,
        parent: Window,
        x: i16,
        y: i16,
        override_redirect: bool,
    };

    pub const ConfigureNotify = extern struct {
        header: request.event.Header,
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
        header: request.event.Header,
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
        header: request.event.Header,
        event: Window,
        window: Window,
        x: i16,
        y: i16,
    };

    pub const ResizeRequest = extern struct {
        header: request.event.Header,
        window: Window,
        width: u16,
        height: u16,
    };

    pub const Place = enum(u8) {
        on_top = 0,
        on_bottom = 1,
    };

    pub const CirculateNotify = extern struct {
        header: request.event.Header,
        event: Window,
        window: Window,
        place: Place,
    };

    pub const CirculateRequest = extern struct {
        header: request.event.Header,
        parent: Window,
        window: Window,
        place: Place,
    };

    pub const PropertyNotify = extern struct {
        header: request.event.Header,
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
        header: request.event.Header,
        time_ms: u32,
        owner: Window,
        selection: Atom,
    };

    pub const SelectionRequest = extern struct {
        header: request.event.Header,
        owner: Window,
        requestor: Window,
        selection: Atom,
        target: Atom,
        property: Atom,
        time_ms: u32,
    };

    pub const SelectionNotify = extern struct {
        header: request.event.Header,
        requestor: Window,
        selection: Atom,
        target: Atom,
        property: Atom,
        time_ms: u32,
    };

    pub const ColormapNotify = extern struct {
        header: request.event.Header,
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
        header: request.event.Header,
        window: Window,
        type: Atom,
        format: Format,
        data: [20]u8, // raw client data

    };

    pub const MappingNotify = extern struct {
        header: request.event.Header,
        request: u8, // Mapping modifier
        first_keycode: u8,
        count: u8,
    };

    pub const NonStandard = extern struct {
        header: request.event.Header,
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

    pub fn next(c: Connection) !?@This() {
        const stream_reader: *std.Io.net.Stream.Reader = @fieldParentPtr("interface", c.reader);
        var pfd = [_]std.posix.pollfd{.{
            .fd = stream_reader.stream.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        const n = try std.posix.poll(&pfd, 1);
        if (n == 0) return null;

        if (pfd[0].revents & std.posix.POLL.IN == 0)
            if ((pfd[0].revents & std.posix.POLL.ERR) != 0) return .close;
        if ((pfd[0].revents & std.posix.POLL.HUP) != 0) return .close;

        c.reader.tossBuffered();
        c.reader.fillMore() catch |err| return switch (err) {
            error.EndOfStream => .close,
            else => err,
        };
        const header = try c.reader.peekStruct(request.event.Header, .little);

        switch (header.response_type) {
            .err => return switch (header.detail) {
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
                else => null,
            },
            .reply => return null,
            else => {},
        }

        return switch (@as(Tag, @enumFromInt(@intFromEnum(header.response_type)))) {
            .key_press => .{ .key_press = try c.reader.takeStruct(Key, .little) },
            .key_release => .{ .key_release = try c.reader.takeStruct(Key, .little) },
            .button_press => .{ .button_press = try c.reader.takeStruct(Button, .little) },
            .button_release => .{ .button_release = try c.reader.takeStruct(Button, .little) },
            .motion_notify => .{ .motion_notify = try c.reader.takeStruct(MotionNotify, .little) },
            .enter_notify => .{ .enter_notify = try c.reader.takeStruct(EnterLeaveNotify, .little) },
            .leave_notify => .{ .leave_notify = try c.reader.takeStruct(EnterLeaveNotify, .little) },
            .focus_in => .{ .focus_in = try c.reader.takeStruct(FocusInOut, .little) },
            .focus_out => .{ .focus_out = try c.reader.takeStruct(FocusInOut, .little) },
            .keymap_notify => .{ .keymap_notify = try c.reader.takeStruct(KeymapNotify, .little) },
            .expose => .{ .expose = try c.reader.takeStruct(Expose, .little) },
            .graphics_expose => .{ .graphics_expose = try c.reader.takeStruct(GraphicsExpose, .little) },
            .no_expose => .{ .no_expose = try c.reader.takeStruct(NoExpose, .little) },
            .visibility_notify => .{ .visibility_notify = try c.reader.takeStruct(VisibilityNotify, .little) },
            .create_notify => .{ .create_notify = try c.reader.takeStruct(CreateNotify, .little) },
            .destroy_notify => .{ .destroy_notify = try c.reader.takeStruct(DestroyNotify, .little) },
            .unmap_notify => .{ .unmap_notify = try c.reader.takeStruct(UnmapNotify, .little) },
            .map_notify => .{ .map_notify = try c.reader.takeStruct(MapNotify, .little) },
            .map_request => .{ .map_request = try c.reader.takeStruct(MapRequest, .little) },
            .reparent_notify => .{ .reparent_notify = try c.reader.takeStruct(ReparentNotify, .little) },
            .configure_notify => .{ .configure_notify = try c.reader.takeStruct(ConfigureNotify, .little) },
            .configure_request => .{ .configure_request = try c.reader.takeStruct(ConfigureRequest, .little) },
            .gravity_notify => .{ .gravity_notify = try c.reader.takeStruct(GravityNotify, .little) },
            .resize_request => .{ .resize_request = try c.reader.takeStruct(ResizeRequest, .little) },
            .circulate_notify => .{ .circulate_notify = try c.reader.takeStruct(CirculateNotify, .little) },
            .circulate_request => .{ .circulate_request = try c.reader.takeStruct(CirculateRequest, .little) },
            .property_notify => .{ .property_notify = try c.reader.takeStruct(PropertyNotify, .little) },
            .selection_clear => .{ .selection_clear = try c.reader.takeStruct(SelectionClear, .little) },
            .selection_request => .{ .selection_request = try c.reader.takeStruct(SelectionRequest, .little) },
            .selection_notify => .{ .selection_notify = try c.reader.takeStruct(SelectionNotify, .little) },
            .colormap_notify => .{ .colormap_notify = try c.reader.takeStruct(ColormapNotify, .little) },
            .client_message => .{ .client_message = try c.reader.takeStruct(ClientMessage, .little) },
            .mapping_notify => .{ .mapping_notify = try c.reader.takeStruct(MappingNotify, .little) },

            else => .{ .non_standard = try c.reader.takeStruct(NonStandard, .little) },
        };
    }
};
