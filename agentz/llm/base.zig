const std = @import("std");

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const LLM = struct {
    ptr: *anyopaque,
    chatFn: *const fn (ptr: *anyopaque, messages: []const ChatMessage) anyerror!void,
    chatStreamFn: *const fn (ptr: *anyopaque, messages: []const ChatMessage) anyerror!void,

    pub fn chat(self: *const LLM, messages: []const ChatMessage) ![]const u8 {
        return self.chatFn(self.ptr, messages);
    }

    pub fn chatStream(self: *const LLM, messages: []const ChatMessage) ![]const u8 {
        return self.chatStream(self.ptr, messages);
    }
};
