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

// Thank you openmymind.net/Zig-Interfaces/
pub const LLM = struct {
    ptr: *const anyopaque,
    chatFn: *const fn (ptr: *const anyopaque, messages: []const ChatMessage) anyerror![]const u8,

    pub fn init(ptr: anytype) LLM {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        return .{
            .ptr = ptr,
            .chatFn = struct {
                pub fn func(pointer: *const anyopaque, messages: []const ChatMessage) anyerror![]const u8 {
                    const self: T = @ptrCast(@alignCast(pointer));
                    return ptr_info.pointer.child.chat(self, messages);
                }
            }.func,
        };
    }

    pub fn chat(self: *const LLM, messages: []const ChatMessage) anyerror![]const u8 {
        return self.chatFn(self.ptr, messages);
    }
};
