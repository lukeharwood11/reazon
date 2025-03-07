const std = @import("std");
const proxz = @import("proxz");

const ArrayList = std.ArrayListUnmanaged(InternalStep);

// const agentz = @import("agentz");
//
// const agent - agentz.Agent(llm, template)
const XML_REACT_PROMPT =
    \\ {s}
    \\
    \\ available tools: {s}
    \\
    \\ ALWAYS follow the following format:
    \\ input: [a user prompt or task]
    \\ thoughts: [you must think about what to do]
    \\ tool: [you must choose a tool to use]
    \\ parameters: [you must pass in parameters in the form of valid JSON. Pass in empty {{}} if no arguments are needed]
    \\ observation: [the output of the tool/parameter call]
    \\ ... repeat the thoughts/tool/parameter/observation seqence until the task is completed.
    \\ thoughts: Given [insert evidence here] I've completed the task/prompt [or "it cannot be done"]
    \\ tool: return
    \\ parameters: {{"text": "[your response to the user]"}}
    \\
    \\ GO!
    \\
    \\ input: {s}
    \\ {s}
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
        _ = allocator; // is this needed?

        var step: InternalStep = undefined;
        step.observation = null;

        std.log.debug("================== Parsing LLM output ================\n{s}", .{slice});
        var lines = std.mem.tokenizeSequence(u8, slice, "\n");
        // parse thoughts
        step.raw = slice;
        if (lines.next()) |line| {
            if (line.len >= "thoughts: ".len) {
                // TODO: do error handling
                step.thoughts = std.mem.trim(u8, line["thoughts: ".len..], "\t ");
            }
        }
        if (lines.next()) |line| {
            if (line.len >= "tool: ".len) {
                // TODO: do error handling
                step.tool = std.mem.trim(u8, line["tool: ".len..], "\t ");
            }
        }
        if (lines.next()) |line| {
            if (line.len >= "parameters: ".len) {
                // TODO do error handling
                step.parameters = std.mem.trim(u8, line["parameters: ".len..], "\t ");
            }
        }
        return step;
    }

    pub fn formatPrompt(self: InternalStep, allocator: std.mem.Allocator) ![]const u8 {
        // TODO: clean this up
        _ = allocator;
        return self.raw;
    }
};

// Note:
// 1. the first arg most likely needs to be of type Tool with anyopaque
// 2. a registered tool either needs to have access to the parent Agent, or it needs to have
// 3. should tools have a handle to the agent?
pub const Tool = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    args: []const Parameter = &.{},
    // change second parameter
    toolFn: *const fn (self: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) anyerror![]const u8,

    pub fn fromStruct(comptime T: type) void {
        _ = T;
        // TODO: implement
        // const tool = Tool.fromType(struct {
        //      pub const description = "This is the description";
        //      pub const args = &[_]Tool.Parameter{.{
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
        for (self.args, 0..) |arg, i| {
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

    /// Should this be runtime/comptime?
    pub fn validate(self: *const Tool) bool {
        // TODO: implement this
        return self.name.len > 0;
    }

    pub fn execute(self: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
        return try self.toolFn(self, allocator, params);
    }
};

pub const ToolManager = struct {
    // Note: refactor to use String type from zig-string or some equivalent (or make your own Luke:)
    // Maybe this should have a reference to the agent? And then the Tool has access to it's manager?
    tools: []const Tool,

    // should pass in an arena allocator
    pub fn describe(self: *const ToolManager, allocator: std.mem.Allocator) ![]const u8 {
        var tool_text: []const u8 = undefined;
        for (self.tools, 0..) |tool, i| {
            const description = try tool.describe(allocator);
            if (i != 0) {
                tool_text = try std.fmt.allocPrint(allocator, "{s}, {s}", .{ tool_text, description });
            } else {
                tool_text = description;
            }
        }
        return tool_text;
    }

    pub fn act(self: *const ToolManager, allocator: std.mem.Allocator, step: InternalStep) ![]const u8 {
        const parameters = std.json.parseFromSliceLeaky(
            std.json.Value,
            allocator,
            step.parameters,
            .{},
        ) catch {
            return "Failed to parse parameters.";
        };
        // TODO: error catch
        for (self.tools) |tool| {
            std.log.info("'{s}' <=> '{s}'", .{ tool.name, step.tool });
            if (std.mem.eql(u8, tool.name, step.tool)) {
                return tool.execute(allocator, parameters.object) catch {
                    return "Error when running tool.";
                };
            }
        }
        return "Error: no tool found with that name.";
    }
};

pub fn getWeather(tool: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
    _ = allocator;
    _ = params;
    _ = tool;
    return "53 and sunny - low chance of rain";
}

const weather_tool: Tool = .{
    .name = "get_weather",
    .description = "Get's weather for the given city",
    .args = &[_]Tool.Parameter{.{
        .name = "city",
        .dtype = .string,
        .description = "The city to search",
    }},
    .toolFn = getWeather,
};

// const return_tool: Tool = .{
//     .name = "return",
//     .description = "when you're ready to respond to the user",
//     .args = &[_]Tool.Parameter{
//         .{
//             .name = "text",
//             .dtype = .string,
//             .description = "response text",
//         },
//     },
// };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var openai = try proxz.OpenAI.init(allocator, .{});
    defer openai.deinit();

    var arr = try ArrayList.initCapacity(allocator, 2);
    defer arr.deinit(allocator);

    const manager: ToolManager = .{
        .tools = &[_]Tool{
            weather_tool,
        },
    };

    const prompt = try std.fmt.allocPrint(allocator, XML_REACT_PROMPT, .{
        "You are a helpful agent who must use tools to answer the user's prompt/question.",
        try manager.describe(arena.allocator()),
        "What is the weather in New Berlin?",
        "",
    });
    defer allocator.free(prompt);

    std.log.info("Prompt:\n{s}", .{prompt});

    const response = try openai.chat.completions.create(.{
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

    const step = try InternalStep.parse(
        allocator,
        response.choices[0].message.content,
    );

    const output = try manager.act(arena.allocator(), step);
    std.log.info("Output: {s}", .{output});
}
