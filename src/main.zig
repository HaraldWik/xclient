const std = @import("std");
const x = @import("xclient");
const request = x.request;
const posix = std.posix;
const mem = std.mem;

const READ_BUFFER_SIZE = 16 * 1024;

// X11 response states
const RESPONSE_STATE_FAILED = 0;
const RESPONSE_STATE_SUCCESS = 1;
const RESPONSE_STATE_AUTHENTICATE = 2;

// X11 opcodes
const X11_REQUEST_MAP_WINDOW = 8;

// Event flags
const X11_EVENT_FLAG_KEY_PRESS = 0x00000001;
const X11_EVENT_FLAG_KEY_RELEASE = 0x00000002;
const X11_EVENT_FLAG_EXPOSURE = 0x8000;

// Window flags
const X11_FLAG_BACKGROUND_PIXEL = 0x00000002;
const X11_FLAG_WIN_EVENT = 0x00000800;

// Window classes
const WINDOWCLASS_COPYFROMPARENT = 0;
const WINDOWCLASS_INPUTOUTPUT = 1;
const WINDOWCLASS_INPUTONLY = 2;

// Globals (same as C)
var GlobalId: u32 = 0;
var GlobalIdBase: u32 = 0;
var GlobalIdMask: u32 = 0;
var GlobalRootWindow: u32 = 0;
var GlobalRootVisualId: u32 = 0;

// PAD macro
fn pad(n: usize) usize {
    return (4 - (n % 4)) % 4;
}

fn verifyOrDie(ok: bool, msg: []const u8) noreturn {
    if (!ok) {
        std.debug.print("{s}\n", .{msg});
        std.process.exit(13);
    }
    unreachable;
}

fn verifyOrDieErrno(ok: bool, msg: []const u8) noreturn {
    if (!ok) {
        std.debug.print("{s}: {}\n", .{ msg, std.posix.errno() });
        std.process.exit(13);
    }
    unreachable;
}

fn getNextId() u32 {
    const result = (GlobalIdMask & GlobalId) | GlobalIdBase;
    GlobalId += 1;
    return result;
}

fn printResponseError(buf: []const u8) void {
    const code = buf[1];
    std.debug.print("\x1b[31mResponse Error: [{d}]\x1b[0m\n", .{code});
}

fn printAndProcessEvent(buf: []const u8) void {
    std.debug.print("Some event occurred: {t}\n", .{@as(x.Event.Type, @enumFromInt(buf[0]))});
}

fn getAndProcessReply(fd: posix.fd_t) !void {
    var buffer: [1024]u8 = undefined;
    const bytes_read = try posix.read(fd, &buffer);
    if (bytes_read == 0) return;

    const code = buffer[0];
    if (code == 0) {
        printResponseError(buffer[0..bytes_read]);
    } else if (code == 1) {
        std.debug.print("---- Unexpected reply\n", .{});
    } else {
        printAndProcessEvent(buffer[0..bytes_read]);
    }
}

// xhost +local: / xhost -local:

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    // Create socket
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    const connection: x.Connection = try .initExplicit(io, x.Connection.default_display_path, null);
    defer connection.close(io);

    var read_buf: [READ_BUFFER_SIZE]u8 = undefined;
    var stream_reader = connection.stream.reader(io, &read_buf);
    const reader = &stream_reader.interface;

    var send_buf: [READ_BUFFER_SIZE]u8 = undefined;
    var stream_writer = connection.stream.writer(io, &send_buf);

    const writer = &stream_writer.interface;

    _ = try connection.stream.socket.receive(io, reader.buffer[0..8]);

    switch (reader.buffer[0]) {
        RESPONSE_STATE_FAILED => {
            std.debug.print("X11 init failed\n", .{});
            return;
        },
        RESPONSE_STATE_AUTHENTICATE => {
            std.debug.print("Authentication required.\nRun: xhost +local:\n", .{});
            return;
        },
        RESPONSE_STATE_SUCCESS => {},
        else => return,
    }

    _ = try connection.stream.socket.receive(io, reader.buffer[8..]);

    const resource_base = mem.readInt(u32, read_buf[12..16], .little);
    const resource_mask = mem.readInt(u32, read_buf[16..20], .little);
    const vendor_len = mem.readInt(u16, read_buf[24..26], .little);
    const num_formats = read_buf[29];

    const vendor_pad = pad(vendor_len);
    const formats_len = 8 * num_formats;
    const screens_offset = 40 + vendor_len + vendor_pad + formats_len;

    const root_window = mem.readInt(u32, read_buf[screens_offset .. screens_offset + 4][0..4], .little);
    const root_visual = mem.readInt(u32, read_buf[screens_offset + 32 .. screens_offset + 36][0..4], .little);

    GlobalIdBase = @intCast(resource_base);
    GlobalIdMask = @intCast(resource_mask);
    GlobalRootWindow = @intCast(root_window);
    GlobalRootVisualId = @intCast(root_visual);

    // Create window
    const window: x.Window = @enumFromInt(getNextId());

    const width: u16 = 600;
    const height: u16 = 300;
    const border_width: u16 = 1;

    const flag_count = 2;
    const request_length: u16 = 8 + flag_count;

    try writer.writeStruct(@as(request.Header, request.Header{
        .opcode = .create_window,
        .length = request_length,
    }), .little);

    const CreateWindow = extern struct {
        window: x.Window, // XID of new window
        parent: x.Window, // root window or parent
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        border_width: u16,
        class: u16, // InputOutput = 1, InputOnly = 2
        visual_id: u32, // usually CopyFromParent
        value_mask: u32, // bitmask for which optional fields to follow
    };

    const create_window: CreateWindow = .{
        .window = window,
        .parent = @enumFromInt(GlobalRootWindow),
        .x = 100,
        .y = 100,
        .width = width,
        .height = height,
        .border_width = border_width,
        .class = WINDOWCLASS_INPUTOUTPUT,
        .visual_id = @bitCast(GlobalRootVisualId),
        .value_mask = X11_FLAG_WIN_EVENT | X11_FLAG_BACKGROUND_PIXEL,
    };
    try writer.writeStruct(create_window, .little);

    try writer.writeInt(u32, 0xffff0000, .little);
    try writer.writeInt(u32, @bitCast(x.Window.EventMask{ .exposure = true, .key_press = true, .key_release = true, .focus_change = true, .button_press = true, .button_release = true }), .little);

    try writer.flush();

    // Map window

    try writer.writeStruct(@as(request.Header, request.Header{
        .opcode = .map_window,
        .length = 2,
    }), .little);
    try writer.writeInt(u32, @intFromEnum(window), .little);
    try writer.flush();

    // Poll loop
    var pfd = [_]posix.pollfd{.{
        .fd = connection.stream.socket.handle,
        .events = posix.POLL.IN,
        .revents = 0,
    }};

    while (true) {
        _ = try posix.poll(&pfd, -1);

        if ((pfd[0].revents & posix.POLL.ERR) != 0) {
            std.debug.print("---- Poll error\n", .{});
        }

        if ((pfd[0].revents & posix.POLL.HUP) != 0) {
            std.debug.print("---- Connection closed\n", .{});
            break;
        }

        try getAndProcessReply(connection.stream.socket.handle);
    }
}
