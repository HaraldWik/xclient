const std = @import("std");
const x = @import("xclient");

pub fn main() !void {
    const connection: x.Connection = try .open();
    defer connection.close();
    try x.auth.send(connection);
    var setup: x.Setup = try .get(connection);

    var buf: [128]u8 = undefined;
    const n = try connection.read(&buf);

    std.debug.print("{s}\n", .{buf[0..n]});

    const window = try x.window.open(connection, &setup, 900, 800);
    std.debug.print("{d}\n", .{@intFromEnum(window)});

    while (true) {}
}
