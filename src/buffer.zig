const std = @import("std");
const Allocator = std.mem.Allocator;

/// A line of text in the buffer.
const Line = struct {
    content: std.ArrayList(u8),

    fn init(allocator: Allocator) Line {
        return .{ .content = std.ArrayList(u8).init(allocator) };
    }

    fn deinit(self: *Line) void {
        self.content.deinit();
    }

    fn clone(self: *const Line, allocator: std.mem.Allocator) !Line {
        var new_line = Line.init(allocator);
        try new_line.content.appendSlice(self.content.items);
        return new_line;
    }
};

/// Text buffer that holds the file content.
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(Line),

    // cursor position in the buffer
    cursor_x: usize = 0,
    cursor_y: usize = 0,

    // viewport offset for scrolling
    viewport_y: usize = 0,
    viewport_x: usize = 0,

    // file information
    file_path: ?[]u8 = null,
    modified: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Buffer {
        var buffer = Buffer{
            .allocator = allocator,
            .lines = std.ArrayList(Line).init(allocator),
        };

        // start with one empty line
        try buffer.lines.append(Line.init(allocator));

        return buffer;
    }

    pub fn deinit(self: *Buffer) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();

        if (self.file_path) |path| {
            self.allocator.free(path);
        }
    }

    /// Load content from a file.
    pub fn loadFile(self: *Buffer, path: []const u8) !void {
        // open the file
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // get file size
        const file_size = try file.getEndPos();

        // read entire file into memory
        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);

        _ = try file.read(content);

        // clear existing content
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.clearRetainingCapacity();

        // parse content into lines
        var line_start: usize = 0;
        for (content, 0..) |byte, i| {
            if (byte == '\n') {
                var new_line = Line.init(self.allocator);

                // handle CRLF by not including \r
                var line_end = i;
                if (i > 0 and content[i - 1] == '\r') {
                    line_end = i - 1;
                }

                if (line_end > line_start) {
                    try new_line.content.appendSlice(content[line_start..line_end]);
                }

                try self.lines.append(new_line);
                line_start = i + 1;
            }
        }

        // add remaining content as last line
        if (line_start < content.len or self.lines.items.len == 0) {
            var new_line = Line.init(self.allocator);
            if (line_start < content.len) {
                try new_line.content.appendSlice(content[line_start..]);
            }
            try self.lines.append(new_line);
        }

        // store file path
        if (self.file_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.file_path = try self.allocator.dupe(u8, path);

        // reset cursor and viewport
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.viewport_x = 0;
        self.viewport_y = 0;
        self.modified = false;
    }

    /// Save content to the current file.
    pub fn saveFile(self: *Buffer) !void {
        if (self.file_path == null) {
            return error.NoFilePathSet;
        }

        try self.saveFileAs(self.file_path.?);
    }

    /// Save content to a specific file.
    pub fn saveFileAs(self: *Buffer, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const writer = file.writer();

        // write lines
        for (self.lines.items, 0..) |*line, i| {
            try writer.writeAll(line.content.items);

            // add newline except for last line if it's empty
            if (i < self.lines.items.len - 1 or line.content.items.len > 0) {
                try writer.writeByte('\n');
            }
        }

        // update file path if different
        if (self.file_path == null or !std.mem.eql(u8, self.file_path.?, path)) {
            if (self.file_path) |old_path| {
                self.allocator.free(old_path);
            }
            self.file_path = try self.allocator.dupe(u8, path);
        }

        self.modified = false;
    }

    /// Get the current line.
    pub fn currentLine(self: *Buffer) *Line {
        return &self.lines.items[self.cursor_y];
    }

    /// Get line at index (returns null if out of bounds).
    pub fn getLine(self: *Buffer, index: usize) ?*Line {
        if (index >= self.lines.items.len) return null;
        return &self.lines.items[index];
    }

    /// Insert a character at the cursor position.
    pub fn insertChar(self: *Buffer, char: u8) !void {
        const line = self.currentLine();
        try line.content.insert(self.cursor_x, char);
        self.cursor_x += 1;
        self.modified = true;
    }

    /// Insert a newline at the cursor position.
    pub fn insertNewline(self: *Buffer) !void {
        const current = self.currentLine();

        // create new line with content after cursor
        var new_line = Line.init(self.allocator);
        if (self.cursor_x < current.content.items.len) {
            try new_line.content.appendSlice(current.content.items[self.cursor_x..]);
            // remove the content after cursor from current line
            current.content.shrinkRetainingCapacity(self.cursor_x);
        }

        // insert the new line after current
        try self.lines.insert(self.cursor_y + 1, new_line);

        // move cursor to beginning of new line
        self.cursor_y += 1;
        self.cursor_x = 0;
        self.modified = true;
    }

    /// Delete character before cursor (backspace).
    pub fn deleteChar(self: *Buffer) !void {
        if (self.cursor_x > 0) {
            // delete within line
            const line = self.currentLine();
            _ = line.content.orderedRemove(self.cursor_x - 1);
            self.cursor_x -= 1;
            self.modified = true;
        } else if (self.cursor_y > 0) {
            // join with previous line
            const current = self.currentLine();
            const prev = &self.lines.items[self.cursor_y - 1];

            self.cursor_x = prev.content.items.len;
            try prev.content.appendSlice(current.content.items);

            current.deinit();
            _ = self.lines.orderedRemove(self.cursor_y);
            self.cursor_y -= 1;
            self.modified = true;
        }
    }

    /// Move cursor with bounds checking.
    pub fn moveCursor(self: *Buffer, dx: i32, dy: i32) void {
        // vertical movement
        if (dy != 0) {
            const new_y = @as(i32, @intCast(self.cursor_y)) + dy;
            if (new_y >= 0 and new_y < self.lines.items.len) {
                self.cursor_y = @intCast(new_y);

                // adjust x to be within line bounds
                const line_len = self.lines.items[self.cursor_y].content.items.len;
                if (self.cursor_x > line_len) {
                    self.cursor_x = line_len;
                }
            }
        }

        // horizontal movement
        if (dx != 0) {
            const line_len = self.currentLine().content.items.len;
            const new_x = @as(i32, @intCast(self.cursor_x)) + dx;

            if (new_x >= 0 and new_x <= line_len) {
                self.cursor_x = @intCast(new_x);
            } else if (new_x < 0 and self.cursor_y > 0) {
                // move to end of previous line
                self.cursor_y -= 1;
                self.cursor_x = self.lines.items[self.cursor_y].content.items.len;
            } else if (new_x > line_len and self.cursor_y < self.lines.items.len - 1) {
                // move to beginning of next line
                self.cursor_y += 1;
                self.cursor_x = 0;
            }
        }
    }

    /// Update viewport to ensure cursor is visible.
    pub fn updateViewport(self: *Buffer, screen_height: usize, screen_width: usize) void {
        // leave room for status line
        const view_height = screen_height - 1;

        // vertical scrolling
        if (self.cursor_y < self.viewport_y) {
            self.viewport_y = self.cursor_y;
        } else if (self.cursor_y >= self.viewport_y + view_height) {
            self.viewport_y = self.cursor_y - view_height + 1;
        }

        // horizontal scrolling
        if (self.cursor_x < self.viewport_x) {
            self.viewport_x = self.cursor_x;
        } else if (self.cursor_x >= self.viewport_x + screen_width) {
            self.viewport_x = self.cursor_x - screen_width + 1;
        }
    }

    /// Get a display name for the buffer.
    pub fn getDisplayName(self: *const Buffer) []const u8 {
        if (self.file_path) |path| {
            // extract just the filename from the path
            return std.fs.path.basename(path);
        }
        return "[No Name]";
    }
};
