const std = @import("std");
const proxz = @import("proxz");
const base = @import("base.zig");

const ChatConfig = base.ChatConfig;
const ArrayList = std.ArrayListUnmanaged;
const LLM = base.LLM;

/// A Chat Implementation for OpenAI models
pub const ChatOpenAI = struct {
    openai: *proxz.OpenAI,
    config: ChatConfig,

    // TODO: merge OpenAIConfig and the ChatConfig
    pub fn init(allocator: std.mem.Allocator, config: ChatConfig) !ChatOpenAI {
        const openai_config: proxz.OpenAIConfig = .{
            .api_key = config.api_key,
            .project = config.project,
            .base_url = config.base_url,
            .organization = config.organization,
            .max_retries = config.max_retries,
        };

        const openai = try proxz.OpenAI.init(allocator, openai_config);
        return .{
            .openai = openai,
            .config = config,
        };
    }

    pub fn deinit(self: *const ChatOpenAI) void {
        self.openai.deinit();
    }

    pub fn chat(self: *const ChatOpenAI, messages: []const base.ChatMessage) ![]const u8 {
        const allocator = self.openai.allocator;
        var chat_request: proxz.completions.ChatCompletionsRequest = undefined;

        // copy everything over that's applicable from the config
        inline for (@typeInfo(ChatConfig).@"struct".fields) |field| {
            if (@hasField(proxz.completions.ChatCompletionsRequest, field.name)) {
                @field(chat_request, field.name) = @field(self.config, field.name);
            }
        }

        // copy over messages
        var arr = try ArrayList(proxz.ChatMessage).initCapacity(allocator, messages.len);
        defer arr.deinit(allocator);

        for (messages) |message| {
            try arr.append(
                allocator,
                .{
                    .content = message.content,
                    .role = message.role,
                },
            );
        }

        chat_request.messages = arr.items;

        const response = try self.openai.chat.completions.create(chat_request);
        defer response.deinit();

        // copy request response out (so caller owns it)
        return try allocator.dupe(
            u8,
            response.choices[0].message.content,
        );
    }

    pub fn llm(self: *const ChatOpenAI) LLM {
        return LLM.init(self);
    }
};
