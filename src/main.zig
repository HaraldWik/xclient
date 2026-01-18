const std = @import("std");
const x = @import("xclient");
const posix = std.posix;
const mem = std.mem;

const READ_BUFFER_SIZE = 16 * 1024;

var GlobalId: u32 = 0;
var GlobalIdBase: u32 = 0;
var GlobalIdMask: u32 = 0;
var GlobalRootWindow: u32 = 0;

fn getNextId() u32 {
    const result = (GlobalIdMask & GlobalId) | GlobalIdBase;
    GlobalId += 1;
    return result;
}

// xhost +local: / xhost -local:

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    const connection: x.Connection = try .initExplicit(io, x.Connection.default_display_path, null);
    defer connection.close();

    var read_buf: [READ_BUFFER_SIZE]u8 = undefined;
    var stream_reader = connection.stream.reader(io, &read_buf);
    const reader = &stream_reader.interface;

    var send_buf: [READ_BUFFER_SIZE]u8 = undefined;
    var stream_writer = connection.stream.writer(io, &send_buf);

    const writer = &stream_writer.interface;

    _ = try connection.stream.socket.receive(io, reader.buffer[0..8]);

    switch (reader.buffer[0]) {
        0 => {
            std.debug.print("X11 init failed\n", .{});
            return;
        },
        2 => {
            std.debug.print("Authentication required.\nRun: xhost +local:\n", .{});
            return;
        },
        1 => {},
        else => return,
    }

    _ = try connection.stream.socket.receive(io, reader.buffer[8..]);

    const resource_base = mem.readInt(u32, read_buf[12..16], .little);
    const resource_mask = mem.readInt(u32, read_buf[16..20], .little);
    const vendor_len = mem.readInt(u16, read_buf[24..26], .little);
    const num_formats = read_buf[29];

    const vendor_pad = (4 - (vendor_len % 4)) % 4;
    const formats_len = 8 * num_formats;
    const screens_offset = 40 + vendor_len + vendor_pad + formats_len;

    const root_window: x.Window = @enumFromInt(mem.readInt(u32, read_buf[screens_offset .. screens_offset + 4][0..4], .little));
    const root_visual: x.VisualID = @enumFromInt(mem.readInt(u32, read_buf[screens_offset + 32 .. screens_offset + 36][0..4], .little));

    GlobalIdBase = @intCast(resource_base);
    GlobalIdMask = @intCast(resource_mask);

    const window: x.Window = @enumFromInt(getNextId());
    try window.create(writer, .{
        .parent = root_window,
        .width = 600,
        .height = 300,
        .border_width = 1,
        .visual_id = root_visual,
    });
    try window.map(writer);
    try writer.flush();

    main_loop: while (true) {
        while (try x.Event.next(connection, reader)) |event| switch (event) {
            .close => {
                std.log.info("close", .{});
                break :main_loop;
            },
            .expose => |expose| std.log.info("resize: {d}x{d}", .{ expose.width, expose.height }),
            .key_press => |key| {
                const keycode = key.header.detail; // This is the hardware key, so its diffrent on diffrent platforms
                std.log.info("pressed key: ({c}) {d}", .{ if (std.ascii.isAlphanumeric(keycode)) keycode else '?', keycode });
            },
            .key_release => {},
            else => |event_type| std.log.info("{t}", .{event_type}),
        };
    }
}
