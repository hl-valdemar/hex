const std = @import("std");
const pterm = @import("pine-terminal");
const Screen = pterm.Screen;
const TermColor = pterm.TermColor;
const DEFAULT_SETTINGS = @import("settings.zig").DEFAULT_SETTINGS;

/// Common size type for widgets.
pub const Size = struct { width: u16, height: u16 };

/// Common position type.
pub const Position = struct { x: u16, y: u16 };

/// Rectangle in screen coordinates.
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn contains(self: Rect, x: u16, y: u16) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    pub fn intersect(self: Rect, other: Rect) ?Rect {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        if (x2 > x1 and y2 > y1) {
            return Rect{
                .x = x1,
                .y = y1,
                .width = x2 - x1,
                .height = y2 - y1,
            };
        }
        return null;
    }
};

/// Border style for windows.
pub const BorderStyle = enum {
    none,
    single,
    double,
    thick,

    pub fn getChars(self: BorderStyle) struct {
        horizontal: u21,
        vertical: u21,
        top_left: u21,
        top_right: u21,
        bottom_left: u21,
        bottom_right: u21,
    } {
        return switch (self) {
            .none => .{
                .horizontal = ' ',
                .vertical = ' ',
                .top_left = ' ',
                .top_right = ' ',
                .bottom_left = ' ',
                .bottom_right = ' ',
            },
            .single => .{
                .horizontal = '─',
                .vertical = '│',
                .top_left = '┌',
                .top_right = '┐',
                .bottom_left = '└',
                .bottom_right = '┘',
            },
            .double => .{
                .horizontal = '═',
                .vertical = '║',
                .top_left = '╔',
                .top_right = '╗',
                .bottom_left = '╚',
                .bottom_right = '╝',
            },
            .thick => .{
                .horizontal = '━',
                .vertical = '┃',
                .top_left = '┏',
                .top_right = '┓',
                .bottom_left = '┗',
                .bottom_right = '┛',
            },
        };
    }
};

/// Base widget interface.
pub const Widget = struct {
    /// Draw the widget to the screen within the given bounds.
    drawFn: *const fn (ptr: *anyopaque, screen: *Screen, bounds: Rect) void,

    /// Get minimum required size.
    getMinSizeFn: *const fn (ptr: *anyopaque) Size,

    /// Handle focus state.
    focusedFn: ?*const fn (ptr: *anyopaque, focused: bool) void = null,

    ptr: *anyopaque,

    pub fn draw(self: Widget, screen: *Screen, bounds: Rect) void {
        self.drawFn(self.ptr, screen, bounds);
    }

    pub fn getMinSize(self: Widget) Size {
        return self.getMinSizeFn(self.ptr);
    }

    pub fn setFocused(self: Widget, focused: bool) void {
        if (self.focusedFn) |f| {
            f(self.ptr, focused);
        }
    }
};

/// Window component that can contain a widget.
pub const Window = struct {
    title: []const u8,
    bounds: Rect,
    border_style: BorderStyle,
    active_border_color: TermColor,
    inactive_border_color: TermColor,
    background_color: TermColor,
    title_color: TermColor,
    child: ?Widget = null,
    focused: bool = false,

    pub fn init(title: []const u8, bounds: Rect) Window {
        return .{
            .title = title,
            .bounds = bounds,
            .border_style = .single,
            .active_border_color = TermColor.fromRGB(
                DEFAULT_SETTINGS.colors.border_active.rgb,
                DEFAULT_SETTINGS.colors.background.rgb,
            ),
            .inactive_border_color = TermColor.fromRGB(
                DEFAULT_SETTINGS.colors.border_inactive.rgb,
                DEFAULT_SETTINGS.colors.background.rgb,
            ),
            .background_color = TermColor.fromRGB(
                DEFAULT_SETTINGS.colors.background.rgb,
                DEFAULT_SETTINGS.colors.background.rgb,
            ),
            .title_color = TermColor.fromRGB(
                DEFAULT_SETTINGS.colors.foreground.rgb,
                DEFAULT_SETTINGS.colors.background.rgb,
            ),
        };
    }

    pub fn draw(self: *const Window, screen: *Screen) void {
        // fill background
        screen.fillRect(
            self.bounds.x,
            self.bounds.y,
            self.bounds.width,
            self.bounds.height,
            ' ',
            self.background_color,
        );

        // draw border
        if (self.border_style != .none) {
            const chars = self.border_style.getChars();
            const color = if (self.focused)
                self.active_border_color
            else
                self.inactive_border_color;

            // corners
            screen.setCell(self.bounds.x, self.bounds.y, chars.top_left, color);
            screen.setCell(self.bounds.x + self.bounds.width - 1, self.bounds.y, chars.top_right, color);
            screen.setCell(self.bounds.x, self.bounds.y + self.bounds.height - 1, chars.bottom_left, color);
            screen.setCell(self.bounds.x + self.bounds.width - 1, self.bounds.y + self.bounds.height - 1, chars.bottom_right, color);

            // horizontal lines
            var i: u16 = 1;
            while (i < self.bounds.width - 1) : (i += 1) {
                screen.setCell(self.bounds.x + i, self.bounds.y, chars.horizontal, color);
                screen.setCell(self.bounds.x + i, self.bounds.y + self.bounds.height - 1, chars.horizontal, color);
            }

            // vertical lines
            i = 1;
            while (i < self.bounds.height - 1) : (i += 1) {
                screen.setCell(self.bounds.x, self.bounds.y + i, chars.vertical, color);
                screen.setCell(self.bounds.x + self.bounds.width - 1, self.bounds.y + i, chars.vertical, color);
            }

            // draw title if present
            if (self.title.len > 0) {
                const max_title_len = if (self.bounds.width > 4) self.bounds.width - 4 else 0;
                const title_len = @min(self.title.len, max_title_len);
                const title_x = self.bounds.x + (self.bounds.width - title_len) / 2;

                screen.setCell(title_x - 1, self.bounds.y, ' ', color);
                screen.drawString(title_x, self.bounds.y, self.title[0..title_len], self.title_color);
                screen.setCell(title_x + title_len, self.bounds.y, ' ', color);
            }
        }

        // draw child widget if present
        if (self.child) |child| {
            const content_bounds = self.getContentBounds();
            child.draw(screen, content_bounds);
        }
    }

    pub fn getContentBounds(self: *const Window) Rect {
        const inset: u16 = if (self.border_style != .none) 1 else 0;
        return Rect{
            .x = self.bounds.x + inset,
            .y = self.bounds.y + inset,
            .width = if (self.bounds.width > 2 * inset) self.bounds.width - 2 * inset else 0,
            .height = if (self.bounds.height > 2 * inset) self.bounds.height - 2 * inset else 0,
        };
    }

    pub fn setChild(self: *Window, child: Widget) void {
        self.child = child;
    }
};

/// Layout system for managing multiple windows.
pub const Layout = struct {
    const WindowNode = struct {
        window: *Window,
        z_order: i32,
    };

    allocator: std.mem.Allocator,
    windows: std.ArrayList(WindowNode),
    focused_index: ?usize = null,

    pub fn init(allocator: std.mem.Allocator) Layout {
        return .{
            .allocator = allocator,
            .windows = std.ArrayList(WindowNode).init(allocator),
        };
    }

    pub fn deinit(self: *Layout) void {
        self.windows.deinit();
    }

    pub fn addWindow(self: *Layout, window: *Window, z_order: i32) !void {
        try self.windows.append(.{
            .window = window,
            .z_order = z_order,
        });

        // sort by z-order
        std.mem.sort(WindowNode, self.windows.items, {}, struct {
            fn lessThan(_: void, a: WindowNode, b: WindowNode) bool {
                return a.z_order < b.z_order;
            }
        }.lessThan);
    }

    pub fn removeWindow(self: *Layout, window: *Window) void {
        for (self.windows.items, 0..) |node, i| {
            if (node.window == window) {
                _ = self.windows.swapRemove(i);
                if (self.focused_index) |idx| {
                    if (idx == i) {
                        self.focused_index = null;
                    } else if (idx > i) {
                        self.focused_index = idx - 1;
                    }
                }
                break;
            }
        }
    }

    pub fn focusWindow(self: *Layout, window: *Window) void {
        // clear previous focus
        if (self.focused_index) |idx| {
            self.windows.items[idx].window.focused = false;
        }

        // set new focus
        for (self.windows.items, 0..) |node, i| {
            if (node.window == window) {
                self.focused_index = i;
                node.window.focused = true;
                break;
            }
        }
    }

    pub fn draw(self: *const Layout, screen: *Screen) void {
        // Draw all windows in z-order
        for (self.windows.items) |node| {
            node.window.draw(screen);
        }
    }
};

/// Text input widget for command buffer.
pub const TextInput = struct {
    allocator: std.mem.Allocator,
    content: std.ArrayList(u8),
    cursor_pos: usize = 0,
    scroll_offset: usize = 0,
    prompt: []const u8 = ":",
    color: TermColor,

    pub fn init(allocator: std.mem.Allocator) !TextInput {
        return TextInput{
            .allocator = allocator,
            .content = std.ArrayList(u8).init(allocator),
            .color = TermColor.fromRGB(
                DEFAULT_SETTINGS.colors.foreground.rgb,
                DEFAULT_SETTINGS.colors.background.rgb,
            ),
        };
    }

    pub fn deinit(self: *TextInput) void {
        self.content.deinit();
    }

    pub fn insertChar(self: *TextInput, char: u8) !void {
        try self.content.insert(self.cursor_pos, char);
        self.cursor_pos += 1;
    }

    pub fn deleteChar(self: *TextInput) void {
        if (self.cursor_pos > 0) {
            _ = self.content.orderedRemove(self.cursor_pos - 1);
            self.cursor_pos -= 1;
        }
    }

    pub fn moveCursor(self: *TextInput, delta: i32) void {
        const new_pos = @as(i32, @intCast(self.cursor_pos)) + delta;
        if (new_pos >= 0 and new_pos <= self.content.items.len) {
            self.cursor_pos = @intCast(new_pos);
        }
    }

    pub fn clear(self: *TextInput) void {
        self.content.clearRetainingCapacity();
        self.cursor_pos = 0;
        self.scroll_offset = 0;
    }

    pub fn getText(self: *const TextInput) []const u8 {
        return self.content.items;
    }

    fn draw(ptr: *anyopaque, screen: *Screen, bounds: Rect) void {
        const self: *const TextInput = @ptrCast(@alignCast(ptr));
        if (bounds.height < 1) return;

        const y = bounds.y + bounds.height / 2;
        var x = bounds.x;

        // draw prompt
        if (self.prompt.len > 0 and x < bounds.x + bounds.width) {
            screen.drawString(x, y, self.prompt, self.color);
            x += @intCast(self.prompt.len);
        }

        // draw content
        const visible_width = if (x < bounds.x + bounds.width)
            bounds.x + bounds.width - x
        else
            0;

        if (visible_width > 0) {
            // update scroll offset to keep cursor visible
            const cursor_screen_pos = self.cursor_pos - self.scroll_offset;
            const scroll_offset = if (cursor_screen_pos >= visible_width)
                self.cursor_pos - visible_width + 1
            else if (self.cursor_pos < self.scroll_offset)
                self.cursor_pos
            else
                self.scroll_offset;

            const end_pos = @min(scroll_offset + visible_width, self.content.items.len);
            if (end_pos > scroll_offset) {
                const visible_text = self.content.items[scroll_offset..end_pos];
                screen.drawString(x, y, visible_text, self.color);
            }
        }
    }

    fn getMinSize(ptr: *anyopaque) Size {
        _ = ptr;
        return .{ .width = 20, .height = 1 };
    }

    pub fn widget(self: *TextInput) Widget {
        return Widget{
            .drawFn = draw,
            .getMinSizeFn = getMinSize,
            .ptr = @ptrCast(self),
        };
    }

    pub fn getCursorScreenPos(self: *TextInput, bounds: Rect) ?Position {
        if (bounds.height < 1) return null;

        const y = bounds.y + bounds.height / 2;
        const prompt_len = self.prompt.len;
        const visible_width = if (bounds.x + prompt_len < bounds.x + bounds.width)
            bounds.x + bounds.width - bounds.x - prompt_len
        else
            0;

        // update scroll offset to keep cursor visible
        if (visible_width > 0) {
            const cursor_screen_pos = self.cursor_pos - self.scroll_offset;
            if (cursor_screen_pos >= visible_width) {
                self.scroll_offset = self.cursor_pos - visible_width + 1;
            } else if (self.cursor_pos < self.scroll_offset) {
                self.scroll_offset = self.cursor_pos;
            }
        }

        const cursor_x = bounds.x + prompt_len + self.cursor_pos - self.scroll_offset;

        if (cursor_x >= bounds.x and cursor_x < bounds.x + bounds.width) {
            return .{ .x = @intCast(cursor_x), .y = y };
        }
        return null;
    }
};
