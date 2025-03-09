const std = @import("std");
const proxz = @import("proxz");
const base = @import("base.zig");

const ArrayList = std.ArrayListUnmanaged;

pub const ChatOpenAI = struct {
    openai: *proxz.OpenAI,

    pub fn init(allocator: std.mem.Allocator, config: proxz.OpenAIConfig) !ChatOpenAI {
        const openai = try proxz.OpenAI.init(allocator, config);
        return .{
            .openai = openai,
        };
    }

    pub fn deinit(self: *const ChatOpenAI) void {
        self.openai.deinit();
    }

    pub fn chat(ptr: *anyopaque, messages: []const base.ChatMessage) ![]const u8 {
        const self: *ChatOpenAI = @ptrCast(@alignCast(ptr));
        const allocator = self.openai.allocator;
        var request_messages = try ArrayList(proxz.ChatMessage).initCapacity(allocator, messages.len);
        for (messages) |message| {
            try request_messages.append(
                allocator,
                .{
                    .role = message.role,
                    .content = message.content,
                },
            );
        }

        // TODO: actually implement this.
        const response = try self.openai.chat.completions.create();
        defer response.deinit();
    }
    pub fn chatStream(_: *anyopaque, _: base.ChatMessage) ![]const u8 {}

    pub fn llm(self: *ChatOpenAI) base.LLM {
        return .{
            .ptr = self,
            .chatFn = chat,
            .chatStreamFn = chatStream,
        };
    }
};
