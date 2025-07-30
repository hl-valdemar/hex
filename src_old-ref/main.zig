const std = @import("std");
const Allocator = std.mem.Allocator;

const Editor = @import("editor.zig").Editor;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // parse command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // if a file path is provided as an argument, open it
    if (args.len > 1) {
        editor.openFile(args[1]) catch |err| {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Error opening file '{s}': {s}\n", .{ args[1], @errorName(err) });
            return;
        };
    }

    try editor.run();
}
