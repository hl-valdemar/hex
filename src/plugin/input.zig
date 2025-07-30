const pecs = @import("pine-ecs");
const pterm = @import("pine-terminal");

const resource = @import("../resource.zig");

pub const Input = pecs.Plugin.init("input", struct {
    pub fn init(registry: *pecs.Registry) anyerror!void {
        // register resources
        try registry.registerResource(pterm.Terminal, .single);
        try registry.registerResource(pterm.KeyEvent, .collection);

        // construct and push necessary resources
        const term = try pterm.Terminal.init(.{
            .alternate_screen = true,
            .hide_cursor = false,
            .enable_mouse = false,
        });
        try registry.pushResource(term);

        // add systems
        try registry.addSystem("update.pre", PollInput);
        try registry.addSystem("update.main", HandleInput);
        try registry.addSystem("flush", ClearInput);
    }

    pub const PollInput = struct {
        pub fn process(_: *PollInput, registry: *pecs.Registry) anyerror!void {
            var term = switch (try registry.queryResource(pterm.Terminal)) {
                .single => |term| term.resource orelse return error.InvalidTermResource,
                .collection => return error.InvalidTermResource,
            };

            if (try term.pollEvent()) |event| {
                switch (event) {
                    .key => |key_event| try registry.pushResource(key_event),
                    else => {},
                }
            }
        }
    };

    pub const HandleInput = struct {
        pub fn process(_: *HandleInput, registry: *pecs.Registry) anyerror!void {
            var key_query = switch (try registry.queryResource(pterm.KeyEvent)) {
                .collection => |col| col,
                .single => return error.InvalidEventResource,
            };
            defer key_query.deinit();

            while (key_query.next()) |key_event| {
                switch (key_event) {
                    .char => |c| if (c == 'q') try registry.pushResource(resource.Message{
                        .shutdown = .requested,
                    }),
                    else => {},
                }
            }
        }
    };

    pub const ClearInput = struct {
        pub fn process(_: *ClearInput, registry: *pecs.Registry) anyerror!void {
            try registry.clearResource(pterm.KeyEvent);
        }
    };
}.init);
