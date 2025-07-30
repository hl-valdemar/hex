pub const Message = union(enum) {
    shutdown: ShutdownReason,

    pub const ShutdownReason = enum {
        requested,
    };
};
