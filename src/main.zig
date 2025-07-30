const std = @import("std");
const pecs = @import("pine-ecs");

const Editor = @import("hexlib").Editor;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.run();
}
