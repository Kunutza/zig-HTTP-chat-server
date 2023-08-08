const std = @import("std");

const print = std.debug.print;

const allocator = std.heap.page_allocator;
const uri = std.Uri.parse("https://ziglang.org/") catch unreachable;

pub fn main() !void {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var req = try client.request(.GET, uri, .{ .allocator = allocator }, .{});
    defer req.deinit();
    try req.start();
    print("waiting..\n", .{});
    try req.wait();
    print("ended\n", .{});

    try std.testing.expect(req.response.status == .ok);
}
