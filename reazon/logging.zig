const std = @import("std");

// Create a scoped logger that the library can use
pub const logger = std.log.scoped(.reazon);

pub const LoggingConfig = struct {};

pub const AgentLogLevel = enum {
    thoughts,
    actions,
    errors,
    none,
};

// TODO: add some colors for pretty logging:)

pub const Colors = struct {
    pub const header = "\x1b[95m";
    pub const ok_blue = "\x1b[94m";
    pub const ok_cyan = "\x1b[96m";
    pub const ok_green = "\x1b[92m";
    pub const warning = "\x1b[93m";
    pub const fail = "\x1b[91m";
    pub const bold = "\x1b[1m";
    pub const underline = "\x1b[4m";
    pub const italic = "\x1b[3m";
    pub const endc = "\x1b[0m";
    pub const none = "";
};

pub fn logInfo(comptime fmt: []const u8, message: []const u8, color: []const u8) void {
    logger.info(
        "{s}" ++ fmt ++ "{s}",
        .{ color, message, if (color.len != 0) Colors.endc else "" },
    );
}
