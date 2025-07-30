const std = @import("std");

pub const std_options = std.Options{
    .log_level = .err,
    .logFn = log.logFn,
};

pub const Editor = @import("editor.zig");
pub const log = @import("log.zig");
