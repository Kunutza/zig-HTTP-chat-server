const std = @import("std");

const mem = std.mem;

pub fn main() !void {
    var recv_buf = [6]u8{ 'S', 't', 'r', 'e', 'e', 't' };
    const recv_slice = recv_buf[0..4];

    var tok_itr = mem.tokenize(u8, recv_slice, " ");
    _ = tok_itr.next();
    std.log.info("{any}", .{tok_itr.next()});
    if (tok_itr.next() != null or !mem.eql(u8, tok_itr.next().?, "GET")) {
        std.log.info("hey", .{});
    }
}
