const std = @import("std");

const net = std.net;
const mem = std.mem;
const fs = std.fs;
const io = std.io;

const ServeFileError = error{ RecvHeaderEOF, RecvHeaderExceededBuffer, HeaderDidNotMatch };

fn serveFile(stream: *const net.Stream, dir: fs.Dir) !void {
    // Receiving
    const file_size: u64 = (try dir.stat()).size;
    std.log.info("size of dir: {d}", .{file_size});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("GPA leaked");
    }

    const recv_buf = try allocator.alloc(u8, file_size);
    defer allocator.free(recv_buf);
    // var recv_buf: [file_size]u8 = undefined;
    var recv_total: usize = 0;

    while (stream.read(recv_buf[recv_total..])) |recv_len| {
        if (recv_len == 0) {
            return ServeFileError.RecvHeaderEOF;
        }

        recv_total += recv_len;

        if (mem.containsAtLeast(u8, recv_buf[0..recv_total], 1, "\r\n\r\n")) {
            break;
        }

        if (recv_total >= recv_len) {
            return ServeFileError.RecvHeaderExceededBuffer;
        }
    } else |err| {
        return err;
    }

    const recv_slice = recv_buf[0..recv_total];
    std.log.info("<<<\n{s}", .{recv_slice});

    // Routing
    var file_path: []const u8 = undefined;
    var tok_itr = mem.tokenize(u8, recv_slice, " ");

    if (!mem.eql(u8, tok_itr.next() orelse "", "GET")) {
        return ServeFileError.HeaderDidNotMatch;
    }

    const path = tok_itr.next() orelse "";
    if (path[0] != '/') {
        return ServeFileError.HeaderDidNotMatch;
    }

    if (mem.eql(u8, path, "/")) {
        file_path = "index";
    } else {
        file_path = path[1..];
    }

    if (!mem.startsWith(u8, tok_itr.rest(), "HTTP/1.1\r\n")) {
        return ServeFileError.HeaderDidNotMatch;
    }

    var file_ext = fs.path.extension(file_path);
    var path_buf: [fs.MAX_PATH_BYTES]u8 = undefined;

    if (file_ext.len == 0) {
        var path_fbs = io.fixedBufferStream(&path_buf);

        try path_fbs.writer().print("{s}.html", .{file_path});
        file_ext = ".html";
        file_path = path_fbs.getWritten();
    }

    std.log.info("Opening {s}", .{file_path});

    var body_file = try dir.openFile(file_path, .{});
    defer body_file.close();

    const file_len = try body_file.getEndPos();

    // Sending
    const http_head =
        "HTTP/1.1 200 OK\r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: {s}\r\n" ++
        "Content-Length: {}\r\n" ++
        "\r\n";
    const mimes = .{ .{ ".html", "text/html" }, .{ ".css", "text/css" }, .{ ".map", "application/json" }, .{ ".svg", "image/svg+xml" }, .{ ".jpg", "image/jpg" }, .{ ".png", "image/png" } };
    var mime: []const u8 = "text/plain";

    inline for (mimes) |kv| {
        if (mem.eql(u8, file_ext, kv[0]))
            mime = kv[1];
    }

    std.log.info(" >>>\n" ++ http_head, .{ mime, file_len });
    try stream.writer().print(http_head, .{ mime, file_len });

    const zero_iovec = &[0]std.os.iovec_const{};
    var send_total: usize = 0;

    while (true) {
        const send_len = try std.os.sendfile(stream.handle, body_file.handle, send_total, file_len, zero_iovec, zero_iovec, 0);

        if (send_len == 0)
            break;

        send_total += send_len;
    }
}

pub fn main() !void {
    var args = std.process.args();
    const exe_name = args.next() orelse "self-serve";
    const public_path = args.next() orelse {
        std.log.err("Usage: {s} <dir to server files from>", .{exe_name});
        return;
    };

    std.log.info("{s}", .{public_path});
    var dir = try fs.cwd().openDir(public_path, .{});
    const self_addr = try net.Address.resolveIp("127.0.0.1", 9000);
    var listener = net.StreamServer.init(.{});
    try (&listener).listen(self_addr);

    std.log.info("Listening on {}; press Ctrl-C to exit...", .{self_addr});
    while ((&listener).accept()) |conn| {
        std.log.info("Accepted Connection from: {}", .{conn.address});

        serveFile(&conn.stream, dir) catch |err| {
            if (@errorReturnTrace()) |bt| {
                std.log.err("Failed to serve client: {}: {}", .{ err, bt });
            } else {
                std.log.err("Failed to serve client: {}", .{err});
            }
        };

        conn.stream.close();
    } else |err| {
        return err;
    }
}
