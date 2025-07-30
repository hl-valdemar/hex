const std = @import("std");
const Allocator = std.mem.Allocator;

const pecs = @import("pine-ecs");
const pterm = @import("pine-terminal");

const log = @import("log.zig");
const resource = @import("resource.zig");
const plugin = @import("plugin/plugin.zig");

pub const Editor = @This();

allocator: Allocator,
registry: pecs.Registry,

pub fn init(allocator: Allocator) !Editor {
    var editor = Editor{
        .allocator = allocator,
        .registry = try pecs.Registry.init(allocator, .{}),
    };
    errdefer editor.deinit();

    // add default stages
    try editor.addStage("startup", .{});
    try editor.addStage("update", .{});
    try editor.addStage("render", .{});
    try editor.addStage("flush", .{});
    try editor.addStage("cleanup", .{});

    // add default substages for update
    const update_stage = editor.getStage("update").?;
    try update_stage.addSubstage("pre", .{});
    try update_stage.addSubstage("main", .{});
    try update_stage.addSubstage("post", .{});

    // add default substages for render
    const render_stage = editor.getStage("render").?;
    try render_stage.addSubstage("pre", .{});
    try render_stage.addSubstage("main", .{});
    try render_stage.addSubstage("post", .{});

    // register critical resources
    try editor.registerResource(resource.Message, .collection);

    // add plugins
    try editor.addPlugin(plugin.Input);
    try editor.addPlugin(plugin.Render);

    return editor;
}

pub fn deinit(self: *Editor) void {
    self.registry.deinit();
}

pub fn run(self: *Editor) !void {
    self.executeStages(&.{"startup"}) catch |err| {
        log.err("startup failed: {}", .{err});
    };

    var should_quit = false;

    while (!should_quit) {
        // execute update and render stages
        self.executeStages(&.{ "update", "render" }) catch |err| {
            log.err("update/render failed: {}", .{err});
        };

        // check for shutdown message
        var messages = switch (try self.queryResource(resource.Message)) {
            .collection => |col| col,
            .single => unreachable,
        };
        defer messages.deinit();

        while (messages.next()) |message| {
            if (message == .shutdown) {
                should_quit = true;
                break;
            }
        }

        self.executeStages(&.{"flush"}) catch |err| {
            log.err("flush failed: {}", .{err});
        };
    }

    self.executeStages(&.{"cleanup"}) catch |err| {
        log.err("cleanup failed: {}", .{err});
    };
}

pub fn addSystem(self: *Editor, stage_path: []const u8, comptime S: type) !void {
    try self.registry.addSystem(stage_path, S);
}

pub fn addSystems(self: *Editor, stage_path: []const u8, comptime systems: anytype) !void {
    try self.registry.addSystems(stage_path, systems);
}

pub fn addPlugin(self: *Editor, plug: pecs.Plugin) !void {
    try self.registry.addPlugin(plug);
}

pub fn addStage(self: *Editor, name: []const u8, config: pecs.StageConfig) !void {
    try self.registry.addStage(name, config);
}

pub fn getStage(self: *Editor, name: []const u8) ?*pecs.Stage {
    return self.registry.getStage(name);
}

pub fn executeStages(self: *Editor, stage_names: []const []const u8) !void {
    try self.registry.executeStages(stage_names);
}

pub fn registerResource(self: *Editor, comptime R: type, kind: pecs.ResourceKind) !void {
    try self.registry.registerResource(R, kind);
}

pub fn pushResource(self: *Editor, res: anytype) !void {
    try self.registry.pushResource(res);
}

pub fn queryResource(self: *Editor, comptime R: type) !pecs.ResourceQuery(R) {
    return self.registry.queryResource(R);
}
