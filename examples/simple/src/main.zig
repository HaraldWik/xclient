const std = @import("std");
const x = @import("xclient");

// xhost +local: / xhost -local:

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    const connection: x.Connection = try .initExplicit(io, x.Connection.default_display_path, null);
    defer connection.close();

    var stream_reader_buffer: [16 * 1024]u8 = undefined;
    var stream_reader = connection.stream.reader(io, &stream_reader_buffer);
    const reader = &stream_reader.interface;

    var stream_writer_buffer: [16 * 1024]u8 = undefined;
    var stream_writer = connection.stream.writer(io, &stream_writer_buffer);
    const writer = &stream_writer.interface;

    var setup, const root = try x.Setup.read(reader);

    const window: x.Window = setup.nextId(x.Window);
    try window.create(writer, .{
        .parent = root.window,
        .width = 600,
        .height = 300,
        .border_width = 1,
        .visual_id = root.visual_id,
    });

    try window.map(writer);
    try writer.flush();

    // const utf8_string_atom: x.Atom = try .getInternal(reader, writer, "UTF8_STRING", false);
    // try window.changeProperty(writer, .replace, .wm_name, utf8_string_atom, .@"8", "Title");

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
