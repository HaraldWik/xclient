const std = @import("std");
const x = @import("xclient");

pub fn main() !void {
    const connection: x.Connection = try .open();
    defer connection.close();
    try x.auth.send(connection);
    var setup: x.Setup = try .get(connection);

    const window: x.Window = try .open(connection, &setup, setup.root_window, null, null, 900, 800);

    std.debug.print("{d}\n", .{@intFromEnum(window)});

    while (true) {}
}
