const std = @import("std");

// module level exports
pub const openai = @import("openai.zig");
pub const groq = @import("groq.zig");
// end module level exports

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
};

// TODO: add some concept of parameter overrides, so that stops can be overriden.

pub const LLM = struct {
    ptr: *const anyopaque,
    chatFn: *const fn (ptr: *const anyopaque, messages: []const ChatMessage) anyerror![]const u8,

    pub fn chat(self: *const LLM, messages: []const ChatMessage) anyerror![]const u8 {
        return self.chatFn(self.ptr, messages);
    }
};
