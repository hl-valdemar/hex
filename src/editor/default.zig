const pterm = @import("pine-terminal");

const Editor = @import("editor.zig");
const resource = @import("resource.zig");
const system = @import("system.zig");

fn setPipeline(self: *Editor) !void {
    try self.addStage("startup", .{});
    try self.addStage("update", .{});
    try self.addStage("render", .{});
    try self.addStage("flush", .{});
    try self.addStage("cleanup", .{});

    // add default substages for update
    const update_stage = self.getStage("update").?;
    try update_stage.addSubstage("pre", .{});
    try update_stage.addSubstage("main", .{});
    try update_stage.addSubstage("post", .{});

    // add default substages for render
    const render_stage = self.getStage("render").?;
    try render_stage.addSubstage("pre", .{});
    try render_stage.addSubstage("main", .{});
    try render_stage.addSubstage("post", .{});
}

fn setResources(self: *Editor) !void {
    // register resources
    try self.registerResource(pterm.Terminal, .single);
    try self.registerResource(pterm.Screen, .single);
    try self.registerResource(pterm.KeyEvent, .collection);
    try self.registerResource(resource.Message, .collection);

    // construct and push resources
    var term = try pterm.Terminal.init(.{
        .alternate_screen = true,
        .hide_cursor = false,
        .enable_mouse = false,
    });
    const screen = try pterm.Screen.init(self.allocator, &term);

    try self.pushResource(term);
    try self.pushResource(screen);
}

fn setSystems(self: *Editor) !void {
    try self.addSystem("update.pre", system.PollInput);
    try self.addSystem("update.main", system.HandleInput);
    try self.addSystem("flush", system.ClearInput);
}
