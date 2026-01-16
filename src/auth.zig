const std = @import("std");
const endian = @import("root.zig").endian;
const Connection = @import("root.zig").Connection;

const name = "MIT-MAGIC-COOKIE-1";

// The header must be 12 bytes
pub const Header = packed struct {
    order: u8 = switch (endian) {
        .little => 'l',
        .big => 'B',
    },
    pad0: u8 = undefined,
    protocol_major: u16 = 11,
    protocol_minor: u16 = 0,
    auth_name_len: u16,
    auth_data_len: u16,
    pad1: u16 = undefined,
};

pub fn init(io: std.Io, minimal: std.process.Init.Minimal, writer: *std.Io.Writer) !void {
    const xauth_path = minimal.environ.getPosix("XAUTHORITY") orelse return error.NoCookiePath;

    var xauth_buffer: [1024]u8 = undefined;
    const dir = try std.Io.Dir.openDirAbsolute(io, std.fs.path.dirname(xauth_path).?, .{});
    const xauth = try dir.readFile(io, std.fs.path.basename(xauth_path), &xauth_buffer);

    var cookie: [32]u8 = undefined;
    const cookie_len = try findCookie(xauth, &cookie);

    const header: Header = .{
        .auth_name_len = @intCast(name.len),
        .auth_data_len = @intCast(cookie_len),
    };

    try writer.writeStruct(header, endian);
    try writer.writeAll(name);
    writer.end += (4 - (writer.end % 4)) % 4; // Padding
    try writer.writeAll(cookie[0..cookie_len]);
    writer.end += (4 - (writer.end % 4)) % 4; // Padding

    try writer.flush();
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
