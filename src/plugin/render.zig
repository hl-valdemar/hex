const std = @import("std");
const Allocator = std.mem.Allocator;

const pecs = @import("pine-ecs");
const pterm = @import("pine-terminal");

const resource = @import("../resource.zig");

pub const Render = pecs.Plugin.init("render", struct {
    pub fn init(registry: *pecs.Registry) anyerror!void {
        // register resources
        try registry.registerResource(pterm.Screen, .single);

        // add systems
        try registry.addSystem("startup", Init);
    }

    // we need an allocator to create the screen
    const Init = struct {
        allocator: Allocator,
        pub fn init(allocator: Allocator) anyerror!Init {
            return Init{ .allocator = allocator };
        }

        pub fn process(self: *Init, registry: *pecs.Registry) anyerror!void {
            var term = switch (try registry.queryResource(pterm.Terminal)) {
                .single => |term| term.resource orelse return error.InvalidTermResource,
                .collection => return error.InvalidTermResource,
            };

            const screen = try pterm.Screen.init(self.allocator, &term);
            try registry.pushResource(screen);
        }
    };
}.init);
