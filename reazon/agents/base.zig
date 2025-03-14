const std = @import("std");
const tools = @import("../tools/base.zig");
const proxz = @import("proxz");
const logging = @import("../logging.zig");
const llm = @import("../llm/base.zig");
pub const templates = @import("template.zig");

const ToolManager = tools.ToolManager;
const Tool = tools.Tool;
const ArrayList = std.ArrayListUnmanaged;
const ChatMessage = llm.ChatMessage;
const AgentTemplate = templates.AgentTemplate;
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
const default_react_prompt =
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
};

pub const Agent = struct {
    config: AgentConfig,
    arena: *std.heap.ArenaAllocator,
    tool_manager: ToolManager,

    pub const AgentConfig = struct {
        tools: []const Tool,
        llm: LLM,
        template: AgentTemplate,
        system_prompt: []const u8 = "You are a helpful assistant.",
        /// The maximum number of thought/action/observation sets the agent will allow.
        max_iterations: usize = 8,
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

    pub fn execute(self: *Agent, input: anytype) ![]const u8 {
        const allocator = self.arena.child_allocator;
        var internal_steps = try ArrayList(InternalStep).initCapacity(allocator, 2);
        defer internal_steps.deinit(allocator);
        var cnt: usize = 0;
        for (0..self.config.max_iterations) |_| {
            const prompt = try self.config.template.formatPrompt(
                self.arena.allocator(),
                input,
                internal_steps.items,
                self.tool_manager,
            );

            const response = try self.config.llm.chat(&[_]ChatMessage{.{
                .role = "user",
                .content = prompt,
            }});
            defer allocator.free(response);

            var step = try self.config.template.parseOutput(
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
            try internal_steps.append(allocator, step);
            if (output.exit) {
                return output.content;
            }
            cnt = cnt + 1;
        }
        return "Error ran out of steps...";
    }
};
