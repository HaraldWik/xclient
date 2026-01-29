const std = @import("std");
pub const request = @import("request.zig");
pub const glx = @import("glx.zig");

pub const Atom = @import("atom.zig").Atom;
pub const Event = @import("event.zig").Event;

pub const Connection = struct {
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    setup: Setup = undefined,
    root_screen: Screen = undefined,
    resource_count: u32 = 0,

    pub const default_display_path = "/tmp/.X11-unix/X0";
    pub const auth_protocol = "MIT-MAGIC-COOKIE-1";

    pub fn init(io: std.Io, reader: *std.Io.Reader, writer: *std.Io.Writer, xauthority: ?[]const u8) !@This() {
        if (xauthority != null) {
            var cookie_buffer: [32]u8 = undefined;
            const cookie_len = try findCookie(io, xauthority.?, &cookie_buffer);
            const cookie = cookie_buffer[0..cookie_len];

            const req: request.Connect = .{
                .auth_name_len = @intCast(auth_protocol.len),
                .auth_data_len = @intCast(cookie.len),
            };

            try writer.writeStruct(req, .little);
            try writer.writeAll(auth_protocol);
            writer.end += (4 - (writer.end % 4)) % 4; // Padding
            try writer.writeAll(cookie[0..cookie_len]);
            writer.end += (4 - (writer.end % 4)) % 4; // Padding
        } else {
            const req: request.Connect = .{};
            try writer.writeStruct(req, .little);
        }

        try writer.flush();

        const setup, const root_screen = try Setup.read(reader);

        return .{
            .reader = reader,
            .writer = writer,
            .setup = setup,
            .root_screen = root_screen,
        };
    }

    pub fn nextId(self: *@This(), comptime T: type) T {
        if (@typeInfo(T).@"enum".tag_type != Id.Tag) @compileError("invalid type given to nextId");
        const id = self.setup.resource_base | (self.resource_count & self.setup.resource_mask);
        self.resource_count += 1;
        return @enumFromInt(id);
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

pub const Id = enum(Tag) {
    _,
    pub const Tag = u32;
};

pub const VisualId = enum(Id.Tag) {
    _,
};

pub const Setup = extern struct {
    // 8-byte header
    status: u8,
    pad0: u8,
    protocol_major: u16,
    protocol_minor: u16,
    length: u16,

    // 40-byte setup info
    release_number: u32,
    resource_base: u32,
    resource_mask: u32,
    motion_buffer_size: u32,

    vendor_len: u16,
    max_request_len: u16,

    num_roots: u8,
    num_formats: u8,

    image_byte_order: u8,
    bitmap_format_bit_order: u8,
    bitmap_format_scanline_unit: u8,
    bitmap_format_scanline_pad: u8,
    min_keycode: u8,
    max_keycode: u8,

    pad1: u32 = undefined,

    pub fn read(reader: *std.Io.Reader) !struct { Setup, Screen } {
        try reader.fillMore();
        defer reader.tossBuffered();
        const setup = try reader.takeStruct(@This(), .little);

        const vendor_pad = (4 - (setup.vendor_len % 4)) % 4;
        const formats_len = 8 * setup.num_formats;
        const screens_offset = setup.vendor_len + vendor_pad + formats_len;
        reader.toss(screens_offset);
        const root = try reader.takeStruct(Screen, .little);

        return .{ setup, root };
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
    visual_id: VisualId,
    backing_stores: u8,
    save_unders: u8,
    root_depth: u8,
    num_depths: u8,
};

pub const Window = enum(Id.Tag) {
    _,

    pub const Config = struct {
        parent: Window,
        x: i16 = 0,
        y: i16 = 0,
        width: u16,
        height: u16,
        border_width: u16,
        visual_id: VisualId,
    };

    /// Same as XSizeHints
    pub const Hints = extern struct {
        flags: Flags,
        x: c_int = 0,
        y: c_int = 0,
        width: c_int = 0,
        height: c_int = 0,
        min_width: c_int = 0,
        min_height: c_int = 0,
        max_width: c_int = 0,
        max_height: c_int = 0,
        width_inc: c_int = 0,
        height_inc: c_int = 0,
        min_aspect: struct_unnamed_8 = .{},
        max_aspect: struct_unnamed_8 = .{},
        base_width: c_int = 0,
        base_height: c_int = 0,
        win_gravity: c_int = 0,

        const struct_unnamed_8 = extern struct {
            x: c_int = 0,
            y: c_int = 0,
        };

        pub const Flags = packed struct(u32) {
            sposition: bool = false,
            ssize: bool = false,
            position: bool = false,
            size: bool = false,
            min_size: bool = false,
            max_size: bool = false,
            resize_inc: bool = false,
            aspect: bool = false,
            base_size: bool = false,
            win_gravity: bool = false,
            pad0: u22 = 0,
        };
    };

    pub fn create(self: @This(), c: Connection, config: Config) !void {
        const flag_count = 2;
        const request_length: u16 = 8 + flag_count;

        const req: request.window.Create = .{
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

        try c.writer.writeStruct(req, .little);

        try c.writer.writeInt(u32, 0x00000000, .little);
        try c.writer.writeStruct(Event.Mask{ .exposure = true, .key_press = true, .key_release = true, .focus_change = true, .button_press = true, .button_release = true }, .little);
    }

    pub fn destroy(self: @This(), c: Connection) void {
        const req: request.window.Destroy = .{ .window = self };
        c.writer.writeStruct(req, .little) catch {};
        c.writer.flush() catch return;
    }

    pub fn map(self: @This(), c: Connection) !void {
        const req: request.window.Map = .{ .window = self };
        try c.writer.writeStruct(req, .little);
    }

    pub fn changeProperty(self: @This(), c: Connection, mode: Property.ChangeMode, property: Atom, @"type": Atom, format: Format, data: []const u8) !void {
        try Property.change(c, mode, self, property, @"type", format, data);
    }

    pub fn setHints(self: @This(), c: Connection, hints: Hints) !void {
        c.reader.tossBuffered();
        try self.changeProperty(c, .append, .wm_size_hints, .atom, .@"32", &std.mem.toBytes(hints));
        try c.reader.fillMore();
        defer c.reader.tossBuffered();

        const reply = try c.reader.takeEnum(request.Reply, .little);
        if (reply != .reply) return error.InvalidReply;
    }
};

pub const Format = enum(u8) {
    @"8" = 8,
    @"16" = 16,
    @"32" = 32,
};

pub const Property = struct {
    pub const Header = extern struct {
        opcode: request.Opcode = .change_property,
        mode: ChangeMode,
        pad0: u16 = undefined,
        window: Window,
        property: Atom,
        type: Atom,
        format: Format,
        pad1: [3]u8 = undefined,
    };

    pub const ChangeMode = enum(u8) {
        replace = 0,
        prepend = 1,
        append = 2,
    };

    pub fn change(c: Connection, mode: ChangeMode, window: Window, property: Atom, @"type": Atom, format: Format, data: []const u8) !void {
        const header: Header = .{
            .mode = mode,
            .window = window,
            .property = property,
            .type = @"type",
            .format = format,
        };
        try c.writer.writeStruct(header, .little);
        const element_count = switch (format) {
            .@"8" => data.len,
            .@"16" => data.len / 2,
            .@"32" => data.len / 4,
        };
        try c.writer.writeInt(u32, @intCast(element_count), .little);
        c.writer.end += (4 - (data.len % 4)) % 4;
        try c.writer.writeAll(data);
        try c.writer.flush();
    }
};

pub const Extension = enum(u8) {
    GLX,
    RANDR,
    XInputExtension,
    Composite,
    @"MIT-SHM",
    _,

    pub fn query(self: @This(), reader: *std.Io.Reader, writer: *std.Io.Writer) !request.extension.QueryReply {
        const name: []const u8 = @tagName(self);

        const req: request.extension.Query = .{
            .header = .{
                .opcode = .query_extension,
                .length = @intCast((@sizeOf(request.extension.Query) + ((name.len + 3) & ~@as(usize, 3))) / 4),
            },
            .name_len = @intCast(name.len),
            .pad0 = 0,
        };
        try writer.writeStruct(req, .little);
        try writer.writeAll(name);
        writer.end += (4 - (writer.end % 4)) % 4;
        try writer.flush();

        try reader.fillMore();
        const reply = try reader.takeStruct(request.extension.QueryReply, .little);

        std.debug.print("{s} = {d}\n", .{ name, reply.major_opcode });

        return reply;
    }
};
