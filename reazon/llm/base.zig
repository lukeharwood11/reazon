const std = @import("std");

// module level exports
pub const openai = @import("openai.zig");
// end module level exports

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
};

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

pub const ChatConfig = struct {
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
