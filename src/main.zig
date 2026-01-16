const std = @import("std");
const x = @import("xclient");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const connection: x.Connection = try .open(io, init.minimal);
    defer connection.close(io);

    var connection_reader_buffer: [4096]u8 = undefined;
    var connection_reader = connection.reader(io, &connection_reader_buffer);
    const reader = &connection_reader.interface;

    var connection_writer_buffer: [4096]u8 = undefined;
    var connection_writer = connection.writer(io, &connection_writer_buffer);
    const writer = &connection_writer.interface;

    try x.auth.init(io, init.minimal, writer);

    var setup: x.Setup = try .get(reader);
    const root = setup.root_screen;

    const window = setup.nextId(x.Window);
    try window.create(
        writer,
        0,
        root.window,
        100,
        200,
        600,
        400,
        0,
        .input_output,
        root.root_visual_id,
        .{ .event_mask = true },
        &.{.{
            .exposure = true,
            .structure_notify = true,
            .key_press = true,
            // .key_release = true,
            // .button_press = true,
            // .button_release = true,
            // .pointer_motion = true,
        }},
    );
    defer window.destroy(writer);
    try window.map(writer);
    try writer.flush();

    while (true) {
        const event_str = try reader.take(32);
        var fixed_event_reader: std.Io.Reader = .fixed(event_str);
        const event_reader = &fixed_event_reader;
        const t: x.Event.Type = @enumFromInt(try event_reader.takeByte());

        switch (t) {
            .gravity_notify => {
                const data = try event_reader.takeStruct(x.Event.GravityNotify, x.endian);
                std.debug.print("DATA: {any}\n", .{data});
            },
            else => switch (t) {
                _ => std.debug.print("event: {d}\n", .{@intFromEnum(t)}),
                else => std.debug.print("event: {t}\n", .{t}),
            },
        }

        reader.tossBuffered();
        // switch (event.type) {
        // _ => std.debug.print("type: {d}\n", .{@intFromEnum(event.type)}),
        // else => std.debug.print("type: {t}\n", .{event.type}),
        // }
    }

    // while (true) {
    //     const event = try reader.takeStruct(XEvent, .little);
    //     switch (event.type) {
    //         EventType.Expose => {
    //             // redraw your window here
    //         },
    //         EventType.KeyPress => {
    //             // handle key press
    //         },
    //         EventType.ButtonPress => {
    //             // handle mouse click
    //         },
    //         else => {},
    //     }
    // }

}
