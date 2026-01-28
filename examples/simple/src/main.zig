const std = @import("std");
const x = @import("xclient");

// xhost +local: / xhost -local:

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    var connection: x.Connection = try .initExplicit(io, x.Connection.default_display_path, null);
    defer connection.close();

    var connection_reader_buffer: [16 * 1024]u8 = undefined;
    var connection_reader = connection.stream.reader(io, &connection_reader_buffer);
    const reader = &connection_reader.interface;

    var connection_writer_buffer: [16 * 1024]u8 = undefined;
    var connection_writer = connection.stream.writer(io, &connection_writer_buffer);
    const writer = &connection_writer.interface;

    const glx = try x.Extension.query(.GLX, reader, writer);
    std.debug.print("glx: {any}\n", .{glx});

    const window: x.Window = connection.nextId(x.Window);
    try window.create(writer, .{
        .parent = connection.root_screen.window,
        .width = 600,
        .height = 300,
        .border_width = 1,
        .visual_id = connection.root_screen.visual_id,
    });
    defer window.destroy(writer);

    try window.map(writer);
    try writer.flush();

    // const utf8_string_atom: x.Atom = try .getInternal(reader, writer, "UTF8_STRING", false);
    // try window.changeProperty(writer, .replace, .wm_name, utf8_string_atom, .@"8", "Title");

    // try window.setHints(reader, writer, .{ .flags = .{ .max_size = true }, .max_width = 900, .max_height = 900 });

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
