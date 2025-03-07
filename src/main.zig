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
    action: []const u8,
    parameters: []const u8,
    observation: ?[]const u8 = null,

    const ParseError = error{
        MissingThoughts,
        MissingAction,
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
                step.thoughts = line["thoughts: ".len..];
            }
        }
        if (lines.next()) |line| {
            if (line.len >= "action: ".len) {
                // TODO: do error handling
                step.action = line["action: ".len..];
            }
        }
        if (lines.next()) |line| {
            if (line.len >= "parameters: ".len) {
                // TODO do error handling
                step.parameters = line["parameters: ".len..];
            }
        }
        return step;
    }

    pub fn format(self: InternalStep, allocator: std.mem.Allocator) ![]const u8 {
        const fmt_string =
            \\<thought>{s}</thought>
            \\<action>{s}</action>
            \\<parameters>{s}</parameters>
            \\<observation>{s}</observation>
        ;
        const string = try std.fmt.allocPrint(
            allocator,
            fmt_string,
            .{
                self.thought,
                self.action,
                self.parameters.?,
                self.observation.?,
            },
        );
        return string;
    }
};

// Note:
// 1. the first arg most likely needs to be of type Tool with anyopaque
// 2. a registered tool either needs to have access to the parent Agent, or it needs to have
pub const Tool = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    args: []Parameter = &.{},
    toolFn: *const fn (allocator: std.mem.Allocator, params: std.json.ObjectMap) anyerror![]const u8,

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

        pub fn describe(self: *const Parameter, allocator: std.mem.Allocator) []const u8 {
            // TODO: add support for description?
            return try std.fmt.allocPrint(allocator, "{}:{}", .{ self.name, std.enums.tagName(DataType, self.type) });
        }
    };

    // should pass in an arena allocator
    pub fn describe(self: *const Tool, allocator: std.mem.Allocator) []const u8 {
        var arg_text: []u8 = "";
        for (self.args, 0..) |arg, i| {
            if (i != 0) {
                arg_text = try std.fmt.allocPrint(allocator, "{s}, {s}", .{ arg_text, arg.describe(allocator) });
            } else {
                arg_text = arg.describe(allocator);
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
};

pub const ToolManager = struct {
    // TODO: lukeharwood11 continue here...
};

pub fn getWeather(allocator: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
    _ = allocator;
    _ = params;
    return "53 and sunny!";
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

const return_tool: Tool = .{
    .name = "return",
    .description = "when you're ready to respond to the user",
    .args = &[_]Tool.Parameter{
        .{
            .name = "text",
            .dtype = .string,
            .description = "response text",
        },
    },
};

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

    const prompt = try std.fmt.allocPrint(allocator, XML_REACT_PROMPT, .{
        "You are a helpful agent who must use tools to answer the user's prompt/question.",
        "return(text: str), get_weather(city: str)",
        "What is the weather in New Berlin?",
        "",
    });
    defer allocator.free(prompt);

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

    std.log.info("{s}", .{response.choices[0].message.content});
}
