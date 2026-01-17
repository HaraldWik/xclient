const std = @import("std");
const x = @import("xclient");
const posix = std.posix;
const mem = std.mem;

const READ_BUFFER_SIZE = 16 * 1024;

// X11 response states
const RESPONSE_STATE_FAILED = 0;
const RESPONSE_STATE_SUCCESS = 1;
const RESPONSE_STATE_AUTHENTICATE = 2;

// X11 opcodes
const X11_REQUEST_CREATE_WINDOW = 1;
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
var GlobalId: i32 = 0;
var GlobalIdBase: i32 = 0;
var GlobalIdMask: i32 = 0;
var GlobalRootWindow: i32 = 0;
var GlobalRootVisualId: i32 = 0;

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

fn getNextId() i32 {
    const result = (GlobalIdMask & GlobalId) | GlobalIdBase;
    GlobalId += 1;
    return result;
}

fn printResponseError(buf: []const u8) void {
    const code = buf[1];
    std.debug.print("\x1b[31mResponse Error: [{d}]\x1b[0m\n", .{code});
}

fn printAndProcessEvent(buf: []const u8) void {
    std.debug.print("Some event occurred: {d}\n", .{buf[0]});
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

pub fn main(minimal: std.process.Init.Minimal) !void {
    // Create socket
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    const connection: x.Connection = try .initExplicit(io, x.Connection.default_display_path, null);
    defer connection.close(io);
    _ = minimal;
    const sock = connection.stream.socket.handle;

    var read_buf: [READ_BUFFER_SIZE]u8 = undefined;
    var stream_reader = connection.stream.reader(io, &read_buf);
    const reader = &stream_reader.interface;

    var send_buf: [READ_BUFFER_SIZE]u8 = undefined;
    var stream_writer = connection.stream.writer(io, &send_buf);

    const writer = &stream_writer.interface;
    _ = writer;
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
    const window_id = getNextId();

    const width: u16 = 600;
    const height: u16 = 300;
    const border_width: u16 = 1;

    const flag_count = 2;
    const request_length: u16 = 8 + flag_count;

    @memset(send_buf[0..], 0);
    send_buf[0] = X11_REQUEST_CREATE_WINDOW;
    send_buf[1] = 0;
    mem.writeInt(u16, send_buf[2..4], request_length, .little);
    mem.writeInt(u32, send_buf[4..8], @bitCast(window_id), .little);
    mem.writeInt(u32, send_buf[8..12], @bitCast(GlobalRootWindow), .little);
    mem.writeInt(i16, send_buf[12..14], 100, .little);
    mem.writeInt(i16, send_buf[14..16], 100, .little);
    mem.writeInt(u16, send_buf[16..18], width, .little);
    mem.writeInt(u16, send_buf[18..20], height, .little);
    mem.writeInt(u16, send_buf[20..22], border_width, .little);
    mem.writeInt(u16, send_buf[22..24], WINDOWCLASS_INPUTOUTPUT, .little);
    mem.writeInt(u32, send_buf[24..28], @bitCast(GlobalRootVisualId), .little);
    mem.writeInt(u32, send_buf[28..32], X11_FLAG_WIN_EVENT | X11_FLAG_BACKGROUND_PIXEL, .little);
    mem.writeInt(u32, send_buf[32..36], 0xff000000, .little);
    mem.writeInt(u32, send_buf[36..40], X11_EVENT_FLAG_EXPOSURE | X11_EVENT_FLAG_KEY_PRESS, .little);

    _ = try posix.write(sock, send_buf[0 .. request_length * 4]);

    // Map window
    @memset(send_buf[0..], 0);
    send_buf[0] = X11_REQUEST_MAP_WINDOW;
    mem.writeInt(u16, send_buf[2..4], 2, .little);
    mem.writeInt(u32, send_buf[4..8], @bitCast(window_id), .little);
    _ = try posix.write(sock, send_buf[0..8]);

    // Poll loop
    var pfd = [_]posix.pollfd{
        .{
            .fd = sock,
            .events = posix.POLL.IN,
            .revents = 0,
        },
    };

    while (true) {
        _ = try posix.poll(&pfd, -1);

        if ((pfd[0].revents & posix.POLL.ERR) != 0) {
            std.debug.print("---- Poll error\n", .{});
        }

        if ((pfd[0].revents & posix.POLL.HUP) != 0) {
            std.debug.print("---- Connection closed\n", .{});
            break;
        }

        try getAndProcessReply(sock);
    }
}
