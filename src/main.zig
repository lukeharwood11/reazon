const std = @import("std");
const proxz = @import("proxz");

const ArrayList = std.ArrayListUnmanaged;

// const agentz = @import("agentz");
//
// const agent - agentz.Agent(llm, template)
const XML_REACT_PROMPT =
    \\{s}
    \\
    \\available tools: {s}
    \\
    \\ALWAYS follow the following format:
    \\input: [a user prompt or task]
    \\thoughts: [you must think about what to do]
    \\tool: [you must choose a tool to use, output just the tool name and place parameters below]
    \\parameters: [you must pass in parameters in the form of valid JSON. Pass in empty {{}} if no arguments are needed]
    \\observation: [the output of the tool/parameter call]
    \\... repeat the thoughts/tool/parameter/observation seqence until the task is completed.
    \\thoughts: Given [insert evidence here] I've completed the task/prompt [or "it cannot be done"]
    \\tool: return
    \\parameters: {{"text": "[your response to the user]"}}
    \\
    \\GO!
    \\
    \\input: {s}
    \\{s}
;

// There should be some concept of a Template that collects imnplementations of interfaces
// i.e. it should have a Formatter (for the prompt) that returns a PromptInput,
// and a Parser (for the response) that returns an InternalStep
const Template = struct {};

const TemplateInput = struct {
    system_prompt: []const u8,
    content: []const u8,
};

/// TODO: implement me so that things can be generic
const StepWriter = struct {};

const ChatMessage = proxz.ChatMessage;

const InternalStep = struct {
    raw: []const u8,
    thoughts: []const u8,
    tool: []const u8,
    parameters: []const u8,
    observation: ?[]const u8 = null,

    const ParseError = error{
        MissingThoughts,
        MissingTool,
        MissingParameters,
    };

    pub fn observe(self: *InternalStep, observation: []const u8) void {
        self.observation = observation;
    }

    pub fn parse(allocator: std.mem.Allocator, slice: []const u8) !InternalStep {
        // split by lines
        var step: InternalStep = undefined;
        step.observation = null;

        std.log.debug("================== Parsing LLM output ================\n{s}", .{slice});
        var lines = std.mem.tokenizeSequence(u8, slice, "\n");
        // parse thoughts
        step.raw = slice;
        if (lines.next()) |line| {
            if (line.len >= "thoughts: ".len) {
                // TODO: do error handling
                step.thoughts = try allocator.dupe(
                    u8,
                    std.mem.trim(u8, line["thoughts: ".len..], "\t "),
                );
            }
        }
        if (lines.next()) |line| {
            if (line.len >= "tool: ".len) {
                // TODO: do error handling
                step.tool = try allocator.dupe(
                    u8,
                    std.mem.trim(u8, line["tool: ".len..], "\t "),
                );
            }
        }
        if (lines.next()) |line| {
            if (line.len >= "parameters: ".len) {
                // TODO do error handling
                step.parameters = try allocator.dupe(
                    u8,
                    std.mem.trim(u8, line["parameters: ".len..], "\t "),
                );
            }
        }
        return step;
    }

    pub fn formatPrompt(self: InternalStep, allocator: std.mem.Allocator) ![]const u8 {
        const FORMAT_STRING =
            \\thoughts: {s}
            \\tool: {s}
            \\parameters: {s}
            \\observation: {s}
        ;
        return try std.fmt.allocPrint(allocator, FORMAT_STRING, .{
            self.thoughts,
            self.tool,
            self.parameters,
            self.observation.?,
        });
    }
};

// Note:
// 1. the first arg most likely needs to be of type Tool with anyopaque
// 2. a registered tool either needs to have access to the parent Agent, or it needs to have
// 3. should tools have a handle to the agent?
pub const Tool = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    params: []const Parameter = &.{},
    // change second parameter
    toolFn: *const fn (self: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) anyerror![]const u8,
    config: Config = .default,

    pub const Config = struct {
        exit: bool = false,
        pub const default: Config = .{};
    };

    pub fn fromStruct(comptime T: type) void {
        _ = T;
        // TODO: implement
        // const tool = Tool.fromType(struct {
        //      pub const description = "This is the description";
        //      pub const params = &[_]Tool.Parameter{.{
        //          .name = "test",
        //          .dtype = .string,
        //          .description = "something to describe",
        //      }};
        //      pub fn my_tool(_: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
        //          return "this is the return";
        //      }
        // });
    }

    pub const Parameter = struct {
        // TODO: add support for more data types
        const DataType = enum {
            string,
            number,
        };

        name: []const u8,
        dtype: DataType,
        description: ?[]const u8 = null,

        pub fn describe(self: *const Parameter, allocator: std.mem.Allocator) ![]const u8 {
            // TODO: add support for description?
            return try std.fmt.allocPrint(allocator, "{s}:{s}", .{
                self.name,
                std.enums.tagName(DataType, self.dtype).?, // compile error would occur
            });
        }
    };

    // should pass in an arena allocator
    pub fn describe(self: *const Tool, allocator: std.mem.Allocator) ![]const u8 {
        var arg_text: []const u8 = undefined;
        for (self.params, 0..) |arg, i| {
            const description = try arg.describe(allocator);
            if (i != 0) {
                arg_text = try std.fmt.allocPrint(allocator, "{s}, {s}", .{ arg_text, description });
            } else {
                arg_text = description;
            }
        }
        const tool_text = try std.fmt.allocPrint(allocator, "{s}({s})", .{
            self.name,
            arg_text,
        });
        return tool_text;
    }

    /// This is a runtime function, since it allows tools to be created dynamically
    pub fn validate(self: *const Tool) bool {
        // TODO:implement this
        return self.name.len > 0;
    }

    pub fn execute(self: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
        return try self.toolFn(self, allocator, params);
    }
};

pub const ToolManager = struct {
    // Note: refactor to use String type from zig-string or some equivalent (or make your own Luke:)
    // Maybe this should have a reference to the agent? And then the Tool has access to it's manager?
    // TODO: future luke: does this need to be a pointer?
    tools: *std.ArrayList(Tool),
    allocator: std.mem.Allocator,

    const return_tool: Tool = .{
        .name = "return",
        .description = "When you know the answer or can't find the answer.",
        .params = &[_]Tool.Parameter{
            .{
                .name = "text",
                .dtype = .string,
                .description = "The output to give to the user",
            },
        },
        .toolFn = struct {
            pub fn toolFn(_: *const Tool, _: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
                const output = params.get("text");
                if (output) |text| {
                    return text.string;
                }
                return "I didn't format my response properly, sorry :(";
            }
        }.toolFn,
        .config = .{ .exit = true },
    };

    pub fn init(allocator: std.mem.Allocator, tools: []const Tool) !ToolManager {
        const arr = try allocator.create(std.ArrayList(Tool));
        arr.* = std.ArrayList(Tool).init(allocator);
        // add all user defined tools
        try arr.appendSlice(tools);
        // allows the agent to exit and respond
        try arr.append(return_tool);
        return .{
            .tools = arr,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ToolManager) void {
        self.tools.deinit();
        self.allocator.destroy(self.tools);
    }

    pub fn register(self: *ToolManager, tool: Tool) !void {
        try self.tools.append(tool);
    }

    pub fn registerMany(self: *ToolManager, tools: []Tool) !void {
        try self.tools.appendSlice(tools);
    }

    pub const ToolOutput = struct {
        exit: bool = false,
        content: []const u8,
    };

    // should pass in an arena allocator
    pub fn describe(self: *const ToolManager, allocator: std.mem.Allocator) ![]const u8 {
        var tool_text: []const u8 = undefined;
        for (self.tools.items, 0..) |tool, i| {
            const description = try tool.describe(allocator);
            if (i != 0) {
                tool_text = try std.fmt.allocPrint(allocator, "{s}, {s}", .{ tool_text, description });
            } else {
                tool_text = description;
            }
        }
        return tool_text;
    }

    pub fn execute(self: *const ToolManager, allocator: std.mem.Allocator, step: InternalStep) !ToolOutput {
        const parameters = std.json.parseFromSliceLeaky(
            std.json.Value,
            allocator,
            step.parameters,
            .{},
        ) catch {
            return .{ .content = "Failed to parse parameters." };
        };
        // TODO: error catch
        for (self.tools.items) |tool| {
            std.log.info("'{s}' <=> '{s}'", .{ tool.name, step.tool });
            if (std.mem.eql(u8, tool.name, step.tool)) {
                const tool_output = tool.execute(allocator, parameters.object) catch {
                    return .{ .content = "Error when running tool." };
                };
                return .{
                    .exit = tool.config.exit,
                    .content = tool_output,
                };
            }
        }
        return .{ .content = "Error: no tool found with that name." };
    }
};

pub const Agent = struct {
    config: AgentConfig,
    arena: *std.heap.ArenaAllocator,
    tool_manager: ToolManager,
    openai: *proxz.OpenAI,

    pub const AgentConfig = struct {
        tools: []const Tool,
        system_prompt: []const u8 = "You are a helpful assistant.",
    };

    pub fn init(allocator: std.mem.Allocator, config: AgentConfig) !Agent {
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        const openai = try proxz.OpenAI.init(allocator, .{});
        const manager = try ToolManager.init(allocator, config.tools);
        return .{
            .config = config,
            .arena = arena,
            .tool_manager = manager,
            .openai = openai,
        };
    }

    pub fn deinit(self: *Agent) void {
        self.arena.deinit();
        self.openai.deinit();

        self.arena.child_allocator.destroy(self.arena);
    }

    pub fn execute(self: *Agent, input: []const u8) ![]const u8 {
        const allocator = self.arena.child_allocator;
        var internal_steps = try ArrayList(InternalStep).initCapacity(allocator, 2);
        defer internal_steps.deinit(allocator);
        var cnt: usize = 0;
        // TODO: add config for max number of steps
        for (0..4) |_| {
            var step_string: []const u8 = "";
            for (internal_steps.items, 0..) |step, i| {
                step_string = try std.fmt.allocPrint(self.arena.allocator(), "{s}{s}{s}", .{
                    step_string,
                    if (i == 0) "" else "\n",
                    try step.formatPrompt(self.arena.allocator()),
                });
            }

            const prompt = try std.fmt.allocPrint(allocator, XML_REACT_PROMPT, .{
                self.config.system_prompt,
                try self.tool_manager.describe(self.arena.allocator()),
                input,
                step_string,
            });
            defer allocator.free(prompt);

            std.log.info("Prompt:\n{s}", .{prompt});

            const response = try self.openai.chat.completions.create(.{
                .model = "gpt-4o-mini",
                .messages = &[_]ChatMessage{
                    .{
                        .role = "user",
                        .content = prompt,
                    },
                },
                .stop = &[_][]const u8{
                    "observation: ",
                },
            });
            defer response.deinit();

            std.log.info("{s}\n==================================", .{response.choices[0].message.content});

            var step = try InternalStep.parse(
                self.arena.allocator(),
                response.choices[0].message.content,
            );

            const output = try self.tool_manager.execute(
                self.arena.allocator(),
                step,
            );
            step.observe(output.content);
            try internal_steps.append(allocator, step);
            if (output.exit) {
                return output.content;
            }
            cnt = cnt + 1;
        }
        return "Error ran out of steps...";
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const weather_tool: Tool = .{
        .name = "get_weather",
        .description = "Get's weather for the given city",
        .params = &[_]Tool.Parameter{.{
            .name = "city",
            .dtype = .string,
            .description = "The city to search",
        }},
        .toolFn = struct {
            pub fn func(_: *const Tool, _: std.mem.Allocator, _: std.json.ObjectMap) ![]const u8 {
                return "53 and sunny - low chance of rain";
            }
        }.func,
    };

    const tools = &[_]Tool{
        weather_tool,
    };

    var agent = try Agent.init(allocator, .{
        .system_prompt = "Answer in old english!",
        .tools = tools,
    });
    defer agent.deinit();

    const response = try agent.execute("What is the weather in new berlin?");
    std.log.info("Main Output: {s}", .{response});
}
