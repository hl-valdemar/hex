const pecs = @import("pine-ecs");
const pterm = @import("pine-terminal");

const resource = @import("resource.zig");

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
