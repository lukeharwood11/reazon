const std = @import("std");
const proxz = @import("proxz");
const base = @import("base.zig");

const ArrayList = std.ArrayListUnmanaged;
const LLM = base.LLM;

pub const OpenAIChatConfig = struct {
    /// Base URL OpenAI client will use, if null will try to pull from `OPENAI_BASE_URL` environment variable.
    base_url: ?[]const u8 = null,

    /// The api key to use, if null will try to pull from `OPENAI_API_KEY` environment variable.
    api_key: ?[]const u8 = null,

    /// The project id to use, if null will try to pull from `OPENAI_PROJECT_ID` environment variable.
    project: ?[]const u8 = null,

    /// The organization id to use, if null will try to pull from `OPENAI_ORG_ID` environment variable.
    organization: ?[]const u8 = null,

    /// The maximum number of retries the client will attempt.
    max_retries: usize = 3,

    /// Required: ID of the model to use
    model: []const u8,

    /// Optional: Whether to store the output of this chat completion request
    /// Defaults to false
    store: ?bool = null,

    /// Optional: Constrains effort on reasoning for reasoning models (o1 and o3-mini models only)
    /// Supported values: "low", "medium", "high"
    /// Defaults to "medium" if left null,
    reasoning_effort: ?[]const u8 = null,

    /// Optional: Number between -2.0 and 2.0
    /// Positive values penalize new tokens based on their existing frequency
    /// Defaults to 0.0 if left null.
    frequency_penalty: ?f32 = null,

    /// Optional: Whether to return log probabilities of output tokens
    /// Defaults to false
    logprobs: ?bool = null,

    /// Optional: Number of most likely tokens to return at each position (0-20)
    /// Requires logprobs to be true
    top_logprobs: ?i32 = null,

    /// Deprecated: Use max_completion_tokens instead
    /// Optional: Maximum tokens to generate
    max_tokens: ?i32 = null,

    /// Optional: Upper bound for generated tokens including visible and reasoning tokens
    max_completion_tokens: ?i32 = null,

    /// Optional: Number of chat completion choices to generate
    /// Defaults to 1 if left null.
    n: ?i32 = null,

    /// Optional: Output types for model to generate (e.g. ["text"], ["text", "audio"])
    /// Defaults to ["text"]
    modalities: ?[][]const u8 = null,

    /// Optional: Number between -2.0 and 2.0
    /// Positive values penalize new tokens based on presence in text
    /// Defaults to 0.0 if left null
    presence_penalty: ?f32 = null,

    /// Optional: Seed for deterministic sampling
    seed: ?i64 = null,

    /// Optional: Latency tier for processing the request
    /// Values: "auto", "default"
    /// Defaults to "auto"
    service_tier: ?[]const u8 = null,

    /// Optional: Up to 4 sequences where API stops generating tokens
    /// An array of strings
    stop: ?[]const []const u8 = null,

    /// Optional: Temperature for sampling (0.0-2.0)
    /// Higher values increase randomness.
    /// Defaults to 1.0 if left null
    temperature: ?f32 = null,

    /// Optional: Alternative to temperature for nucleus sampling (0.0-1.0)
    /// Defaults to 1.0 if left null
    top_p: ?f32 = null,

    /// Optional: Unique identifier for end-user
    user: ?[]const u8 = null,
};

/// A Chat Implementation for OpenAI models
pub const ChatOpenAI = struct {
    openai: *proxz.OpenAI,
    config: OpenAIChatConfig,

    // TODO: merge OpenAIConfig and the OpenAIChatConfig
    pub fn init(allocator: std.mem.Allocator, config: OpenAIChatConfig) !ChatOpenAI {
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
        inline for (@typeInfo(OpenAIChatConfig).@"struct".fields) |field| {
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
