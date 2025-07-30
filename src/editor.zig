const std = @import("std");
const Allocator = std.mem.Allocator;

const pterm = @import("pine-terminal");
const Terminal = pterm.Terminal;
const Screen = pterm.Screen;
const Event = pterm.Event;
const TermColor = pterm.TermColor;

const Buffer = @import("buffer.zig").Buffer;
const ui = @import("ui.zig");

const DEFAULT_SETTINGS = @import("settings.zig").DEFAULT_SETTINGS;

const Mode = enum { normal, insert, command };

/// Buffer view widget for displaying buffer content.
const BufferView = struct {
    buffer: *Buffer,
    show_line_numbers: bool = true,
    line_number_color: TermColor,
    text_color: TermColor,

    fn draw(ptr: *anyopaque, screen: *Screen, bounds: ui.Rect) void {
        const self: *const BufferView = @ptrCast(@alignCast(ptr));
        if (bounds.height == 0 or bounds.width == 0) return;

        self.buffer.updateViewport(bounds.height, bounds.width);

        const line_num_width: u16 = if (self.show_line_numbers) 5 else 0;
        var y: u16 = 0;

        while (y < bounds.height) : (y += 1) {
            const buffer_y = self.buffer.viewport_y + y;

            if (self.buffer.getLine(buffer_y)) |line| {
                var x: u16 = 0;

                // draw line number
                if (self.show_line_numbers) {
                    var num_buf: [8]u8 = undefined;
                    const num_str = std.fmt.bufPrint(&num_buf, "{d:4} ", .{buffer_y + 1}) catch "???? ";
                    screen.drawString(bounds.x, bounds.y + y, num_str, self.line_number_color);
                    x = line_num_width;
                }

                // draw line content
                const content_start = if (x < bounds.width) bounds.x + x else bounds.x + bounds.width;
                const content_width = if (x < bounds.width) bounds.width - x else 0;

                for (line.content.items, 0..) |char, char_idx| {
                    if (char_idx >= self.buffer.viewport_x and
                        x < line_num_width + content_width)
                    {
                        screen.setCell(content_start + x - line_num_width, bounds.y + y, char, self.text_color);
                        x += 1;
                    }
                }
            } else { // empty line indicator
                screen.setCell(bounds.x, bounds.y + y, '~', TermColor.fromRGB(
                    DEFAULT_SETTINGS.colors.foreground.rgb,
                    DEFAULT_SETTINGS.colors.background.rgb,
                ));
            }
        }
    }

    fn getMinSize(ptr: *anyopaque) ui.Size {
        _ = ptr;
        return .{ .width = 40, .height = 10 };
    }

    pub fn widget(self: *BufferView) ui.Widget {
        return ui.Widget{
            .drawFn = draw,
            .getMinSizeFn = getMinSize,
            .ptr = @ptrCast(self),
        };
    }

    pub fn getCursorScreenPos(self: *const BufferView, bounds: ui.Rect) ui.Position {
        const line_num_width: u16 = if (self.show_line_numbers) 5 else 0;
        const cursor_screen_x = bounds.x + line_num_width + self.buffer.cursor_x - self.buffer.viewport_x;
        const cursor_screen_y = bounds.y + self.buffer.cursor_y - self.buffer.viewport_y;
        return .{ .x = @as(u16, @intCast(cursor_screen_x)), .y = @as(u16, @intCast(cursor_screen_y)) };
    }
};

/// Status bar widget.
const StatusBar = struct {
    mode: Mode,
    buffer: *Buffer,
    color: TermColor,
    message: ?[]const u8 = null,

    fn draw(ptr: *anyopaque, screen: *Screen, bounds: ui.Rect) void {
        const self: *const StatusBar = @ptrCast(@alignCast(ptr));
        if (bounds.height < 1) return;

        // fill background
        screen.fillRect(bounds.x, bounds.y, bounds.width, 1, ' ', self.color);

        // mode indicator
        const mode_str = switch (self.mode) {
            .normal => "[NORMAL]",
            .insert => "[INSERT]",
            .command => "[COMMAND]",
        };
        screen.drawString(bounds.x + 1, bounds.y, mode_str, self.color);

        // position info
        var pos_buf: [32]u8 = undefined;
        const pos_str = std.fmt.bufPrint(&pos_buf, "{d}:{d}", .{
            self.buffer.cursor_y + 1,
            self.buffer.cursor_x + 1,
        }) catch "?:?";

        const pos_x = if (bounds.width > pos_str.len + 1)
            bounds.x + bounds.width - pos_str.len - 1
        else
            bounds.x;
        screen.drawString(@as(u16, @intCast(pos_x)), bounds.y, pos_str, self.color);

        // message (if any)
        if (self.message) |msg| {
            const msg_x = bounds.x + mode_str.len + 2;
            const max_msg_len = if (pos_x > msg_x + 2) pos_x - msg_x - 2 else 0;
            if (max_msg_len > 0) {
                const msg_len = @min(msg.len, max_msg_len);
                screen.drawString(@as(u16, @intCast(msg_x)), bounds.y, msg[0..msg_len], self.color);
            }
        }
    }

    fn getMinSize(ptr: *anyopaque) ui.Size {
        _ = ptr;
        return .{ .width = 40, .height = 1 };
    }

    pub fn widget(self: *StatusBar) ui.Widget {
        return ui.Widget{
            .drawFn = draw,
            .getMinSizeFn = getMinSize,
            .ptr = @ptrCast(self),
        };
    }
};

/// Simple text editor with proper UI components.
pub const Editor = struct {
    allocator: Allocator,
    term: Terminal,
    screen: Screen,
    layout: ui.Layout,

    // buffers
    buffers: std.ArrayList(Buffer),
    current_buffer: usize,

    // ui components (heap allocated to maintain stable pointers)
    main_window: *ui.Window,
    buffer_view: *BufferView,
    status_bar: *StatusBar,

    command_window: ?*ui.Window = null,
    command_input: ?*ui.TextInput = null,

    // state
    mode: Mode,
    running: bool = true,
    message: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        var term = try Terminal.init(.{
            .alternate_screen = true,
            .hide_cursor = false,
        });
        errdefer term.deinit();

        var screen = try Screen.init(allocator, &term);
        errdefer screen.deinit();

        var default_buffer = try Buffer.init(allocator);
        errdefer default_buffer.deinit();

        var buffers = std.ArrayList(Buffer).init(allocator);
        errdefer buffers.deinit();

        try buffers.append(default_buffer);
        errdefer _ = buffers.pop();

        const size = try term.getSize();

        // create ui components on heap
        const main_window = try allocator.create(ui.Window);
        errdefer allocator.destroy(main_window);

        main_window.* = ui.Window.init("", ui.Rect{
            .x = 0,
            .y = 0,
            .width = size.width,
            .height = size.height - 1, // leave room for status bar
        });
        main_window.border_style = .double;

        const buffer_view = try allocator.create(BufferView);
        errdefer allocator.destroy(buffer_view);

        buffer_view.* = BufferView{
            .buffer = &buffers.items[0],
            .line_number_color = TermColor.fromRGB(
                DEFAULT_SETTINGS.colors.foreground.rgb,
                DEFAULT_SETTINGS.colors.background.rgb,
            ),
            .text_color = TermColor.fromRGB(
                DEFAULT_SETTINGS.colors.foreground.rgb,
                DEFAULT_SETTINGS.colors.background.rgb,
            ),
        };

        const status_bar = try allocator.create(StatusBar);
        errdefer allocator.destroy(status_bar);

        status_bar.* = StatusBar{
            .mode = .normal,
            .buffer = &buffers.items[0],
            .color = TermColor.fromRGB(
                DEFAULT_SETTINGS.colors.background.rgb,
                DEFAULT_SETTINGS.colors.foreground.rgb,
            ),
        };

        var layout = ui.Layout.init(allocator);
        errdefer layout.deinit();

        // set up main window
        main_window.setChild(buffer_view.widget());
        try layout.addWindow(main_window, 0);

        return Editor{
            .allocator = allocator,
            .term = term,
            .screen = screen,
            .layout = layout,
            .buffers = buffers,
            .current_buffer = 0,
            .main_window = main_window,
            .buffer_view = buffer_view,
            .status_bar = status_bar,
            .mode = .normal,
        };
    }

    pub fn deinit(self: *Editor) void {
        if (self.command_window) |window| {
            self.allocator.destroy(window);
        }

        if (self.command_input) |input| {
            input.deinit();
            self.allocator.destroy(input);
        }

        for (self.buffers.items) |*buffer| {
            buffer.deinit();
        }
        self.buffers.deinit();

        self.layout.deinit();

        self.allocator.destroy(self.main_window);
        self.allocator.destroy(self.buffer_view);
        self.allocator.destroy(self.status_bar);

        self.screen.deinit();
        self.term.deinit();
    }

    pub fn run(self: *Editor) !void {
        while (self.running) {
            try self.render();
            try self.handleInput();
            // small delay to avoid busy loop
            std.time.sleep(5_000_000); // 5ms
        }
    }

    fn render(self: *Editor) !void {
        const size = try self.term.getSize();

        // update component sizes
        self.main_window.bounds.width = size.width;
        self.main_window.bounds.height = size.height - 1;

        self.screen.clear();

        // draw all windows
        self.layout.draw(&self.screen);

        // draw status bar (always on top)
        self.status_bar.mode = self.mode;
        self.status_bar.message = self.message;
        const status_widget = self.status_bar.widget();
        status_widget.draw(&self.screen, ui.Rect{
            .x = 0,
            .y = size.height - 1,
            .width = size.width,
            .height = 1,
        });

        // position cursor
        if (self.command_window != null and self.command_input != null) {
            // command mode - position cursor in command input
            const cmd_bounds = self.command_window.?.getContentBounds();
            if (self.command_input.?.getCursorScreenPos(cmd_bounds)) |pos| {
                try self.term.setCursor(pos.x + 1, pos.y + 1);
            }
        } else {
            // normal/insert mode - position cursor in buffer
            const main_bounds = self.main_window.getContentBounds();
            const cursor_pos = self.buffer_view.getCursorScreenPos(main_bounds);
            try self.term.setCursor(cursor_pos.x + 1, cursor_pos.y + 1);
        }

        try self.screen.render();
    }

    fn enterCommandMode(self: *Editor) !void {
        self.mode = .command;

        // create command input on heap
        const input = try self.allocator.create(ui.TextInput);
        input.* = try ui.TextInput.init(self.allocator);
        self.command_input = input;

        // create command window on heap
        const size = try self.term.getSize();
        const cmd_height = 3;
        const cmd_width = @min(size.width / 2, 60);

        const window = try self.allocator.create(ui.Window);
        window.* = ui.Window.init("Command", ui.Rect{
            .x = (size.width - cmd_width) / 2,
            .y = size.height / 2 - cmd_height / 2,
            .width = cmd_width,
            .height = cmd_height,
        });

        window.border_style = .double;
        window.background_color = TermColor.fromRGB(
            DEFAULT_SETTINGS.colors.background.rgb,
            DEFAULT_SETTINGS.colors.background.rgb,
        );
        window.setChild(input.widget());

        self.command_window = window;

        try self.layout.addWindow(window, 100);
        self.layout.focusWindow(window);
    }

    fn exitCommandMode(self: *Editor) void {
        if (self.command_window) |window| {
            self.layout.removeWindow(window);
            self.allocator.destroy(window);
            self.command_window = null;
        }

        if (self.command_input) |input| {
            input.deinit();
            self.allocator.destroy(input);
            self.command_input = null;
        }

        self.mode = .normal;
        self.layout.focusWindow(self.main_window);
    }

    fn executeCommand(self: *Editor) !void {
        if (self.command_input) |*input| {
            const command = input.*.getText();
            defer self.exitCommandMode();

            // parse and execute command
            const trimmed = std.mem.trim(u8, command, " ");
            if (std.mem.eql(u8, trimmed, "q") or std.mem.eql(u8, trimmed, "quit")) {
                self.running = false;
            } else if (std.mem.eql(u8, trimmed, "w") or std.mem.eql(u8, trimmed, "write")) {
                self.message = "Would save file (not implemented)";
            } else if (trimmed.len > 0) {
                self.message = "Unknown command";
            }
        }
    }

    fn handleInput(self: *Editor) !void {
        if (try self.term.pollEvent()) |event| {
            // update current buffer reference
            self.buffer_view.buffer = &self.buffers.items[self.current_buffer];
            self.status_bar.buffer = &self.buffers.items[self.current_buffer];

            switch (self.mode) {
                .normal => try self.handleNormalMode(event),
                .insert => try self.handleInsertMode(event),
                .command => try self.handleCommandMode(event),
            }
        }
    }

    fn handleNormalMode(self: *Editor, event: Event) !void {
        switch (event) {
            .key => |key| switch (key) {
                .char => |c| switch (c) {
                    'i' => {
                        self.mode = .insert;
                        self.message = null;
                    },
                    ':' => try self.enterCommandMode(),
                    'h' => self.buffers.items[self.current_buffer].moveCursor(-1, 0),
                    'l' => self.buffers.items[self.current_buffer].moveCursor(1, 0),
                    'j' => self.buffers.items[self.current_buffer].moveCursor(0, 1),
                    'k' => self.buffers.items[self.current_buffer].moveCursor(0, -1),
                    else => {},
                },
                .ctrl => |c| switch (c) {
                    'q' => self.running = false,
                    else => {},
                },
                else => {},
            },
            else => {},
        }
    }

    fn handleInsertMode(self: *Editor, event: Event) !void {
        switch (event) {
            .key => |key| switch (key) {
                .char => |c| {
                    if (c >= 32 and c <= 126) {
                        try self.buffers.items[self.current_buffer].insertChar(c);
                    }
                },
                .special => |special| switch (special) {
                    .escape => {
                        self.mode = .normal;
                        self.message = null;
                    },
                    .enter => try self.buffers.items[self.current_buffer].insertNewline(),
                    .backspace => try self.buffers.items[self.current_buffer].deleteChar(),
                    else => {},
                },
                .arrow => |arrow| {
                    const buffer = &self.buffers.items[self.current_buffer];
                    switch (arrow) {
                        .up => buffer.moveCursor(0, -1),
                        .down => buffer.moveCursor(0, 1),
                        .left => buffer.moveCursor(-1, 0),
                        .right => buffer.moveCursor(1, 0),
                    }
                },
                else => {},
            },
            else => {},
        }
    }

    fn handleCommandMode(self: *Editor, event: Event) !void {
        if (self.command_input == null) return;

        switch (event) {
            .key => |key| switch (key) {
                .char => |c| {
                    if (c >= 32 and c <= 126) {
                        try self.command_input.?.insertChar(c);
                    }
                },
                .special => |special| switch (special) {
                    .escape => self.exitCommandMode(),
                    .enter => try self.executeCommand(),
                    .backspace => self.command_input.?.deleteChar(),
                    else => {},
                },
                .arrow => |arrow| switch (arrow) {
                    .left => self.command_input.?.moveCursor(-1),
                    .right => self.command_input.?.moveCursor(1),
                    else => {},
                },
                else => {},
            },
            else => {},
        }
    }
};
