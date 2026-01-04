const std = @import("std");
const Connection = @import("root.zig").Connection;

const name = "MIT-MAGIC-COOKIE-1";

pub fn send(connection: Connection) !void {
    const xauth_path = std.posix.getenv("XAUTHORITY") orelse return error.NoCookiePath;
    const xauth_fd: std.posix.fd_t = try std.posix.openZ(xauth_path.ptr, .{}, 0);
    defer std.posix.close(xauth_fd);

    var xauth_buf: [1024]u8 = undefined;
    const n = try std.posix.read(xauth_fd, xauth_buf[0..]);

    var cookie: [32]u8 = undefined;
    const cookie_len = try findCookie(xauth_buf[0..n], &cookie);

    var header: [12]u8 = @splat(0);
    header[0] = 'l';
    std.mem.writeInt(u16, header[2..4], 11, .little); // protocol_major
    std.mem.writeInt(u16, header[4..6], 0, .little); // protocol_minor
    std.mem.writeInt(u16, header[6..8], @intCast(name.len), .little); // auth_name_len
    std.mem.writeInt(u16, header[8..10], @intCast(cookie_len), .little); // auth_data_len

    var buffer: [512]u8 = undefined;
    @memcpy(buffer[0..header.len], header[0..]); // write header bytes
    var pos: usize = header.len;

    // write auth_name
    @memcpy(buffer[pos .. pos + name.len], name);
    pos += name.len;

    // pad auth_name to 4 bytes
    const name_pad = (4 - (pos % 4)) % 4;
    for (0..name_pad) |i| {
        buffer[pos + i] = 0;
    }
    pos += name_pad;

    // write cookie
    @memcpy(buffer[pos .. pos + cookie_len], cookie[0..cookie_len]);
    pos += cookie_len;

    // pad cookie to 4 bytes
    const cookie_pad = (4 - (pos % 4)) % 4;
    for (0..cookie_pad) |i| {
        buffer[pos + i] = 0;
    }
    pos += cookie_pad;

    // send handshake
    var written: usize = 0;
    while (written < pos) written += try std.posix.write(connection.sock, buffer[written..pos]);
}

pub fn findCookie(xauth_file: []const u8, buf: []u8) !usize {
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

        if (std.mem.eql(u8, name_bytes, name)) {
            if (data_len > buf.len) return error.BufferTooSmall;
            @memcpy(buf[0..data_len], data_bytes);
            return data_len;
        }
    }

    return error.CookieNotFound;
}
