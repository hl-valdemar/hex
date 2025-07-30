const std = @import("std");
const Allocator = std.mem.Allocator;

const pterm = @import("pine-terminal");
const Terminal = pterm.Terminal;
const Screen = pterm.Screen;
const Event = pterm.Event;
const TermColor = pterm.TermColor;

const Buffer = @import("buffer.zig").Buffer;

const Mode = enum { normal, insert };

/// Simple text editor.
pub const Editor = struct {
    allocator: Allocator,
    term: Terminal,
    screen: Screen,
    buffers: std.ArrayList(Buffer),
    command_buffer: ?Buffer,
    current_buffer: usize,
    mode: Mode,
    running: bool = true,

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

        return Editor{
            .allocator = allocator,
            .term = term,
            .screen = screen,
            .buffers = buffers,
            .current_buffer = 0,
            .command_buffer = null,
            .mode = .normal,
        };
    }

    pub fn deinit(self: *Editor) void {
        for (self.buffers.items) |*buffer| {
            buffer.deinit();
        }
        self.buffers.deinit();

        if (self.command_buffer) |*buffer| {
            buffer.deinit();
        }

        self.screen.deinit();
        self.term.deinit();
    }

    pub fn run(self: *Editor) !void {
        while (self.running) {
            try self.render();
            try self.handleInput();
        }
    }

    fn render(self: *Editor) !void {
        const size = try self.term.getSize();
        self.buffers.items[self.current_buffer].updateViewport(size.height, size.width);

        self.screen.clear();

        // render buffer content
        const view_height = size.height - 1; // leave room for status line
        var screen_y: u16 = 0;

        while (screen_y < view_height) : (screen_y += 1) {
            const buffer_y = self.buffers.items[self.current_buffer].viewport_y + screen_y;

            if (self.buffers.items[self.current_buffer].getLine(buffer_y)) |line| {
                // render line number
                var num_buf: [8]u8 = undefined;
                const num_str = try std.fmt.bufPrint(&num_buf, "{d:4} ", .{buffer_y + 1});
                self.screen.drawString(0, screen_y, num_str, TermColor.fromPalette(8, 0));

                // render line content
                const line_start_x: u16 = 5;
                var screen_x: u16 = line_start_x;

                for (line.content.items, 0..) |char, char_idx| {
                    if (char_idx >= self.buffers.items[self.current_buffer].viewport_x and screen_x < size.width) {
                        self.screen.setCell(screen_x, screen_y, char, TermColor.fromPalette(7, 0));
                        screen_x += 1;
                    }
                }
            } else {
                // empty line indicator
                self.screen.setCell(0, screen_y, '~', TermColor.fromPalette(8, 0));
            }
        }

        // render status line
        // const status_y = size.height - 1;
        // self.screen.fillRect(0, status_y, size.width, 1, ' ', TermColor.fromPalette(0, 7));
        //
        // var status_buf: [256]u8 = undefined;
        // const status = try std.fmt.bufPrint(&status_buf, " {d}:{d} | Lines: {d} | ^Q to quit ", .{
        //     self.buffer.cursor_y + 1,
        //     self.buffer.cursor_x + 1,
        //     self.buffer.lines.items.len,
        // });
        // self.screen.drawString(0, status_y, status, TermColor.fromPalette(0, 7));

        // render command buffer (if present)
        if (self.command_buffer) |*buffer| {
            const command_box_height = 3;
            const command_box_width = @divTrunc(size.width, 3);
            const command_box_tag = "COMMAND";

            self.screen.fillRect(
                0,
                size.height - command_box_height,
                command_box_width,
                command_box_height,
                ' ',
                TermColor.fromPalette(0, 7),
            );
            self.screen.drawString(
                command_box_width - @as(u16, @intCast(command_box_tag.len)) - 2,
                size.height - command_box_height,
                command_box_tag,
                TermColor.fromPalette(0, 7),
            );

            const line_start_x: u16 = 0;
            var screen_x: u16 = line_start_x;
            screen_y = size.height - command_box_height + @divTrunc(command_box_height, 2);

            if (buffer.getLine(0)) |line| {
                self.screen.setCell(screen_x, screen_y, ' ', TermColor.fromPalette(0, 7));
                for (line.content.items, 0..) |char, char_idx| {
                    if (char_idx >= buffer.viewport_x and screen_x + 1 < size.width) {
                        self.screen.setCell(screen_x + 1, screen_y, char, TermColor.fromPalette(0, 7));
                        screen_x += 1;
                    }
                }
            }
        }

        // position cursor
        if (self.command_buffer) |buffer| {
            const line_start_x: u16 = 0;
            const cursor_screen_x: u16 = line_start_x + @as(u16, @intCast(buffer.cursor_x - buffer.viewport_x)) + 1;
            const cursor_screen_y = size.height - 2;
            try self.term.setCursor(@intCast(cursor_screen_x + 1), @intCast(cursor_screen_y + 1));
        } else { // else current normal buffer
            const cursor_screen_x = 5 + self.buffers.items[self.current_buffer].cursor_x - self.buffers.items[self.current_buffer].viewport_x;
            const cursor_screen_y = self.buffers.items[self.current_buffer].cursor_y - self.buffers.items[self.current_buffer].viewport_y;
            try self.term.setCursor(@intCast(cursor_screen_x + 1), @intCast(cursor_screen_y + 1));
        }

        try self.screen.render();
        std.time.sleep(5_000_000); // 5ms to avoid flicker
    }

    fn handleInput(self: *Editor) !void {
        if (try self.term.pollEvent()) |event| {
            switch (self.mode) {
                .normal => {
                    switch (event) {
                        .key => |key| switch (key) {
                            .char => |c| {
                                switch (c) {
                                    'i' => self.mode = .insert,
                                    ':' => { // spawn command buffer
                                        if (self.command_buffer == null) {
                                            self.command_buffer = try Buffer.init(self.allocator);
                                            self.mode = .insert;
                                        }
                                    },
                                    'h' => {
                                        if (self.command_buffer) |*buffer| {
                                            buffer.moveCursor(-1, 0);
                                        } else {
                                            self.buffers.items[self.current_buffer].moveCursor(-1, 0);
                                        }
                                    },
                                    'l' => {
                                        if (self.command_buffer) |*buffer| {
                                            buffer.moveCursor(1, 0);
                                        } else {
                                            self.buffers.items[self.current_buffer].moveCursor(1, 0);
                                        }
                                    },
                                    'j' => {
                                        if (self.command_buffer) |*buffer| {
                                            buffer.moveCursor(0, 1);
                                        } else {
                                            self.buffers.items[self.current_buffer].moveCursor(0, 1);
                                        }
                                    },
                                    'k' => {
                                        if (self.command_buffer) |*buffer| {
                                            buffer.moveCursor(0, -1);
                                        } else {
                                            self.buffers.items[self.current_buffer].moveCursor(0, -1);
                                        }
                                    },
                                    else => {},
                                }
                            },
                            .special => |special| switch (special) {
                                .enter => {
                                    if (self.command_buffer) |*buffer| {
                                        const command = buffer.getLine(0).?.content.items;

                                        self.parseCommand(command);

                                        buffer.deinit();
                                        self.command_buffer = null;
                                    }
                                },
                                .escape => {
                                    if (self.command_buffer) |*buffer| {
                                        buffer.deinit();
                                        self.command_buffer = null;
                                    }
                                },
                                else => {},
                            },
                            else => {},
                        },
                        else => {},
                    }
                },
                .insert => {
                    switch (event) {
                        .key => |key| switch (key) {
                            .char => |c| {
                                if (c >= 32 and c <= 126) {
                                    if (self.command_buffer) |*buffer| {
                                        try buffer.insertChar(c);
                                    } else {
                                        try self.buffers.items[self.current_buffer].insertChar(c);
                                    }
                                }
                            },
                            .ctrl => |c| switch (c) {
                                'q' => self.running = false,
                                else => {},
                            },
                            .arrow => |arrow| switch (arrow) {
                                .up => self.buffers.items[self.current_buffer].moveCursor(0, -1),
                                .down => self.buffers.items[self.current_buffer].moveCursor(0, 1),
                                .left => self.buffers.items[self.current_buffer].moveCursor(-1, 0),
                                .right => self.buffers.items[self.current_buffer].moveCursor(1, 0),
                            },
                            .special => |special| switch (special) {
                                .enter => {
                                    if (self.command_buffer) |*buffer| {
                                        const command = buffer.getLine(0).?.content.items;

                                        self.parseCommand(command);

                                        buffer.deinit();
                                        self.command_buffer = null;
                                    } else {
                                        try self.buffers.items[self.current_buffer].insertNewline();
                                    }
                                },
                                .backspace => {
                                    if (self.command_buffer) |*buffer| {
                                        try buffer.deleteChar();
                                    } else {
                                        try self.buffers.items[self.current_buffer].deleteChar();
                                    }
                                },
                                .escape => self.mode = .normal,
                                else => {},
                            },
                            else => {},
                        },
                        else => {},
                    }
                },
            }
        }
    }

    fn parseCommand(self: *Editor, command: []const u8) void {
        const stripped = std.mem.trim(u8, command, " ");
        if (std.mem.eql(u8, stripped, "q") or std.mem.eql(u8, stripped, "quit")) {
            self.running = false;
        }
    }
};
