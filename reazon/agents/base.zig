const std = @import("std");
const tools = @import("../tools/base.zig");
const proxz = @import("proxz");
const logging = @import("../logging.zig");
const llm = @import("../llm/base.zig");

const ToolManager = tools.ToolManager;
const Tool = tools.Tool;
const ArrayList = std.ArrayListUnmanaged;
const ChatMessage = llm.ChatMessage;
const LLM = llm.LLM;

// const reazon = @import("reazon");
//
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

// const agent - reazon.Agent(llm, template)
const DEFAULT_REACT_PROMPT =
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

pub const InternalStep = struct {
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

        var lines = std.mem.tokenizeSequence(u8, slice, "\n");
        // parse thoughts
        step.raw = try allocator.dupe(u8, slice);
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
        // FIXME: if the string can't be parsed correctly, this will print an invalid output.
        // Switch to display `raw` if it wasn't parsed.
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

pub const Agent = struct {
    config: AgentConfig,
    arena: *std.heap.ArenaAllocator,
    tool_manager: ToolManager,

    pub const AgentConfig = struct {
        tools: []const Tool,
        llm: *const LLM,
        system_prompt: []const u8 = "You are a helpful assistant.",
    };

    pub fn init(allocator: std.mem.Allocator, config: AgentConfig) !Agent {
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.child_allocator.destroy(arena);
        errdefer arena.deinit();

        const manager = try ToolManager.init(allocator, config.tools);
        return .{
            .config = config,
            .arena = arena,
            .tool_manager = manager,
        };
    }

    pub fn deinit(self: *Agent) void {
        self.tool_manager.deinit();
        self.arena.deinit();

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

            const prompt = try std.fmt.allocPrint(allocator, DEFAULT_REACT_PROMPT, .{
                self.config.system_prompt,
                try self.tool_manager.describe(self.arena.allocator()),
                input,
                step_string,
            });
            defer allocator.free(prompt);

            const response = try self.config.llm.chat(&[_]ChatMessage{.{
                .role = "user",
                .content = prompt,
            }});
            defer allocator.free(response);

            var step = try InternalStep.parse(
                self.arena.allocator(),
                response,
            );

            logging.logInfo("LLM thought: {s}", step.thoughts, logging.Colors.ok_green ++ logging.Colors.bold ++ logging.Colors.italic);
            logging.logInfo("{s}", step.tool, logging.Colors.bold ++ logging.Colors.italic);

            const output = try self.tool_manager.execute(
                self.arena.allocator(),
                step,
            );
            logging.logInfo("{s}", output.content, logging.Colors.fail ++ logging.Colors.bold ++ logging.Colors.italic);

            step.observe(output.content);
            logging.logInfo("{s}", step.thoughts, logging.Colors.ok_green ++ logging.Colors.bold ++ logging.Colors.italic);
            try internal_steps.append(allocator, step);
            if (output.exit) {
                return output.content;
            }
            cnt = cnt + 1;
        }
        return "Error ran out of steps...";
    }
};
