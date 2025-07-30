const std = @import("std");

const Editor = @import("hexlib").Editor;
const log = @import("hexlib").log;
const pecs = @import("pine-ecs");

pub const std_options = std.Options{
    .log_level = .err,
    .logFn = log.logFn,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.run();
}
