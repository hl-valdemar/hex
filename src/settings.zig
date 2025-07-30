const ColorValue = @import("pine-terminal").ColorValue;
const colors = @import("pine-terminal").colors;

pub const Settings = struct {
    colors: struct {
        background: ColorValue = .{ .rgb = .{ .r = 20, .g = 20, .b = 20 } },
        foreground: ColorValue = .{ .rgb = .{ .r = 200, .g = 200, .b = 200 } },
        border_inactive: ColorValue = .{ .rgb = .{ .r = 100, .g = 100, .b = 100 } },
        border_active: ColorValue = .{ .rgb = .{ .r = 150, .g = 150, .b = 150 } },
    } = .{},
};

pub const DEFAULT_SETTINGS = Settings{};
