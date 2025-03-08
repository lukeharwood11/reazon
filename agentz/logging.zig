const std = @import("std");

// Create a scoped logger that the library can use
pub const logger = std.log.scoped(.agentz);

pub const LoggingConfig = struct {};

// TODO: add some colors for pretty logging:)
