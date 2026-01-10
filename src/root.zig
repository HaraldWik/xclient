const std = @import("std");

pub const auth = @import("auth.zig");

pub const ID = enum(Tag) {
    _,

    pub const Tag = u32;
};

pub const Connection = struct {
    sock: std.posix.socket_t,

    pub fn open() !@This() {
        const display = std.c.getenv("DISPLAY") orelse return error.NoDisplay;
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
    root_window: Window,

    pub fn get(connection: Connection) !@This() {
        const allocator = std.heap.page_allocator;
        // Fixed setup reply header is 32 bytes
        var header: [32]u8 = undefined;
        var read_total: usize = 0;

        while (read_total < header.len) {
            const n = try connection.read(header[read_total..]);
            if (n == 0) return error.ServerClosedConnection;
            read_total += n;
        }

        // reply_length is in 4-byte units, excluding the first 8 bytes
        const reply_len_words =
            std.mem.readInt(u16, header[6..8], .little);
        const full_len: usize = 8 + @as(usize, reply_len_words) * 4;

        var reply = try allocator.alloc(u8, full_len);
        defer allocator.free(reply);

        @memcpy(reply[0..32], header[0..32]);

        // Read the remaining bytes
        read_total = 32;
        while (read_total < full_len) {
            const n = try connection.read(reply[read_total..]);
            if (n == 0) return error.ServerClosedConnection;
            read_total += n;
        }

        // ---- Correct field offsets ----
        const vendor_len =
            std.mem.readInt(u16, reply[24..26], .little);
        const screen_count = reply[28];
        const format_count = reply[29];

        if (screen_count == 0)
            return error.NoScreens;

        var offset: usize = 32;

        // Vendor string (padded to 4 bytes)
        offset += std.mem.alignForward(usize, vendor_len, 4);

        // Pixmap formats (8 bytes each)
        offset += @as(usize, format_count) * 8;

        // First screen → root window
        const root_window =
            std.mem.readInt(u32, reply[offset .. offset + 4][0..4], .little);

        return .{
            .resource_counter = 1,
            .resource_id_base = std.mem.readInt(u32, reply[12..16][0..4], .little),
            .resource_id_mask = std.mem.readInt(u32, reply[16..20][0..4], .little),
            .root_window = @enumFromInt(root_window),
        };
    }

    pub fn nextId(self: *@This()) ID {
        const id = self.resource_id_base | (self.resource_counter & self.resource_id_mask);
        self.resource_counter += 1;
        return @enumFromInt(id);
    }
};

pub const Window = enum(ID.Tag) {
    _,

    pub fn open(connection: Connection, setup: *Setup, root_window: @This(), x: ?u16, y: ?u16, width: u16, height: u16) !@This() {
        const id = setup.nextId();

        var buf: [64]u8 = @splat(0);
        var pos: usize = 0;

        buf[pos] = 1; // CreateWindow opcode
        pos += 1;
        buf[pos] = 0; // padding
        pos += 1;

        // length in 4-byte units (we’ll fix later)
        pos += 2;

        // window ID
        std.mem.writeInt(u32, buf[pos .. pos + 4][0..4], @intFromEnum(id), .little);
        pos += 4;

        // parent = root window (we’ll assume 0 for now)
        std.mem.writeInt(u32, buf[pos .. pos + 4][0..4], @intFromEnum(root_window), .little);
        pos += 4;

        // x, y, width, height
        std.mem.writeInt(u16, buf[pos .. pos + 2][0..2], x orelse 0, .little);
        pos += 2;
        std.mem.writeInt(u16, buf[pos .. pos + 2][0..2], y orelse 0, .little);
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
        std.mem.writeInt(u16, buf[pos .. pos + 2][0..2], 0, .little);
        pos += 2;

        // length in 4-byte units
        const length: u16 = @intCast(pos / 4);
        std.mem.writeInt(u16, buf[2..4], length, .little);

        var written: usize = 0;
        while (written < pos) written += try std.posix.write(connection.sock, buf[written..pos]);

        return @enumFromInt(@intFromEnum(id));
    }
};
