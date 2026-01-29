const std = @import("std");
const x = @import("xclient");

// xhost +local: / xhost -local:

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    const address: std.Io.net.UnixAddress = try .init(x.Connection.default_display_path);
    const stream = try address.connect(io);
    defer stream.close(io);

    var stream_reader_buffer: [@sizeOf(x.request.Connect) + @sizeOf(x.Screen) + @sizeOf(x.Setup) + 32]u8 = undefined;
    var stream_reader = stream.reader(io, &stream_reader_buffer);
    const reader = &stream_reader.interface;

    var stream_writer_buffer: [@sizeOf(x.request.Connect)]u8 = undefined;
    var stream_writer = stream.writer(io, &stream_writer_buffer);
    const writer = &stream_writer.interface;

    var connection: x.Connection = try .init(io, reader, writer, null);

    const glx = try x.Extension.query(.GLX, reader, writer);
    std.debug.print("glx: {any}\n", .{glx});

    const window: x.Window = connection.nextId(x.Window);
    try window.create(connection, .{
        .parent = connection.root_screen.window,
        .width = 600,
        .height = 300,
        .border_width = 1,
        .visual_id = connection.root_screen.visual_id,
    });
    defer window.destroy(connection);

    try window.map(connection);
    try connection.writer.flush();

    // const utf8_string_atom: x.Atom = try .getInternal(reader, writer, "UTF8_STRING", false);
    // try window.changeProperty(writer, .replace, .wm_name, utf8_string_atom, .@"8", "Title");

    // try window.setHints(reader, writer, .{ .flags = .{ .max_size = true }, .max_width = 900, .max_height = 900 });

    main_loop: while (true) {
        while (try x.Event.next(connection)) |event| switch (event) {
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
