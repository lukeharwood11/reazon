const std = @import("std");
const proxz = @import("proxz");
const base = @import("base.zig");

const ArrayList = std.ArrayListUnmanaged;

pub const OpenAIChatConfig = struct {
    /// Required: ID of the model to use
    model: []const u8,

    /// Optional: Whether to store the output of this chat completion request
    /// Defaults to false
    store: ?bool = null,

    /// Optional: Constrains effort on reasoning for reasoning models (o1 and o3-mini models only)
    /// Supported values: "low", "medium", "high"
    /// Defaults to "medium" if left null,
    reasoning_effort: ?[]const u8 = null,

    // Optional: Set of key-value pairs for storing additional information
    // TODO: implement metadata parameter as StringHashMap
    // metadata: StringHashMap([]const u8),

    /// Optional: Number between -2.0 and 2.0
    /// Positive values penalize new tokens based on their existing frequency
    /// Defaults to 0.0 if left null.
    frequency_penalty: ?f32 = null,

    // Optional: Modify likelihood of specified tokens appearing in completion
    // TODO: implement logit_bias parameter as IntegerHashMap
    // logit_bias: IntegerHashMap(f32),

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

    // Optional: Configuration for Predicted Output
    // TODO: implement prediction parameter as struct
    // prediction: PredictionConfig,

    // Optional: Parameters for audio output
    // TODO: implement audio parameter as struct
    // audio: AudioConfig,

    /// Optional: Number between -2.0 and 2.0
    /// Positive values penalize new tokens based on presence in text
    /// Defaults to 0.0 if left null
    presence_penalty: ?f32 = null,

    // Optional: Format specification for model output
    // TODO: implement response_format parameter as union
    // response_format: ResponseFormat,

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

    // Optional: List of tools (functions) the model may call
    // TODO: implement tools parameter as array of structs
    // tools: []Tool,

    // Optional: Controls which tool is called by the model
    // TODO: implement tool_choice parameter as union
    // tool_choice: ToolChoice,

    // Optional: Enable parallel function calling during tool use
    // Defaults to true
    // TODO: implement parallel_tool_calls
    // parallel_tool_calls: bool = true,

    /// Optional: Unique identifier for end-user
    user: ?[]const u8 = null,
};

/// A Chat Implementation for OpenAI models
pub const ChatOpenAI = struct {
    openai: *proxz.OpenAI,
    chat_config: OpenAIChatConfig,

    // TODO: merge OpenAIConfig and the OpenAIChatConfig
    pub fn init(allocator: std.mem.Allocator, config: proxz.OpenAIConfig, chat_config: OpenAIChatConfig) !ChatOpenAI {
        const openai = try proxz.OpenAI.init(allocator, config);
        return .{
            .openai = openai,
            .chat_config = chat_config,
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
                @field(chat_request, field.name) = @field(self.chat_config, field.name);
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

    pub fn llm(self: *const ChatOpenAI) base.LLM {
        return base.LLM.init(self);
    }
};
