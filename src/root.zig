const std = @import("std");

pub const auth = @import("auth.zig");

pub const ID = enum(u32) {
    _,
};

pub const Connection = struct {
    sock: std.posix.socket_t,

    pub fn open() !@This() {
        const display = std.posix.getenv("DISPLAY") orelse return error.NoDisplay;
        var path_buf: [108]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "/tmp/.X11-unix/X{s}\x00", .{display[1..]});

        const sock = try std.posix.socket(std.posix.system.AF.UNIX, std.posix.system.SOCK.STREAM, 0);
        errdefer std.posix.close(sock);

        var addr: std.posix.sockaddr.un = .{ .path = path_buf };
        const addr_len: u32 = @intCast(@offsetOf(std.posix.sockaddr.un, "path") + path.len);

        try std.posix.connect(sock, @ptrCast(&addr), addr_len);

        return .{ .sock = sock };
    }

    pub fn close(self: @This()) void {
        std.posix.close(self.sock);
    }

    pub fn read(self: @This(), buf: []u8) !usize {
        const n = try std.posix.read(self.sock, buf);
        if (n == 0) return error.ServerClosedConnection;
        return n;
    }

    pub fn validate(self: @This()) !void {
        var header: [8]u8 = undefined;

        var total: usize = 0;
        while (total < header.len) : (total += 0) {
            const n = try self.read(header[total..]);
            total += n;
        }

        switch (header[0]) {
            0 => return error.Failure,
            1 => return,
            2 => return error.AuthenticationRequired,
            else => return error.UnknownReply,
        }
    }
};

pub const Setup = struct {
    resource_counter: u32,
    resource_id_base: u32,
    resource_id_mask: u32,

    pub fn get(connection: Connection) !@This() {
        var buf: [24]u8 = undefined;
        var total: usize = 0;

        while (total < buf.len) {
            const n = try connection.read(buf[total..]);
            if (n == 0) return error.ServerClosedConnection;
            total += n;
        }

        return .{
            .resource_counter = 1,
            .resource_id_base = std.mem.readInt(u32, buf[12..16], .little),
            .resource_id_mask = std.mem.readInt(u32, buf[16..20], .little),
        };
    }

    pub fn nextId(self: *@This()) ID {
        const id = self.resource_id_base | (self.resource_counter & self.resource_id_mask);
        self.resource_counter += 1;
        return @enumFromInt(id);
    }
};

pub const window = struct {
    pub fn open(connection: Connection, setup: *Setup, width: u16, height: u16) !ID {
        const win_id = setup.nextId();

        var buf: [64]u8 = @splat(0);
        var pos: usize = 0;

        buf[pos] = 1; // CreateWindow opcode
        pos += 1;
        buf[pos] = 0; // padding
        pos += 1;

        // length in 4-byte units (we’ll fix later)
        pos += 2;

        // window ID
        std.mem.writeInt(u32, buf[pos .. pos + 4][0..4], @intFromEnum(win_id), .little);
        pos += 4;

        // parent = root window (we’ll assume 0 for now)
        std.mem.writeInt(u32, buf[pos .. pos + 4][0..4], 0, .little);
        pos += 4;

        // x, y, width, height
        std.mem.writeInt(u16, buf[pos .. pos + 2][0..2], 0, .little);
        pos += 2;
        std.mem.writeInt(u16, buf[pos .. pos + 2][0..2], 0, .little);
        pos += 2;
        std.mem.writeInt(u16, buf[pos .. pos + 2][0..2], width, .little);
        pos += 2;
        std.mem.writeInt(u16, buf[pos .. pos + 2][0..2], height, .little);
        pos += 2;

        // border width
        std.mem.writeInt(u16, buf[pos .. pos + 2][0..2], 0, .little);
        pos += 2;

        // depth
        buf[pos] = 0x01;
        pos += 1;

        // class
        buf[pos] = 1;
        pos += 1;

        // visual = CopyFromParent
        pos += 2;

        // length in 4-byte units
        const length: u16 = @intCast(pos / 4);
        std.mem.writeInt(u16, buf[2..4], length, .little);

        // send to server
        var written: usize = 0;
        while (written < pos) written += try std.posix.write(connection.sock, buf[written..pos]);

        try connection.validate();

        return win_id;
    }
};
