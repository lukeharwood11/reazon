const std = @import("std");
const base = @import("base.zig");
const templ = @import("template.zig");
const tools = @import("../tools/base.zig");

const InternalStep = base.InternalStep;
const AgentTemplate = templ.AgentTemplate;

pub const ReactAgentTemplate = struct {
    system_prompt: []const u8,

    pub const stop = &[_][]const u8{"observation: "};

    const prompt =
        \\{s}
        \\
        \\available tools: {s}
        \\
        \\ALWAYS follow the following format:
        \\input: [a user prompt or task]
        \\thoughts: [you must think about what to do]
        \\tool: [you must choose a tool to use, output just the tool name (parameters should be passed on the parameters line)]
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

    pub const default: ReactAgentTemplate = .{
        .system_prompt = "You are a helpful agent.",
    };

    fn formatInternalStep(step: InternalStep, allocator: std.mem.Allocator) ![]const u8 {
        // FIXME: if the string can't be parsed correctly, this will print an invalid output.
        // Switch to display `raw` if it wasn't parsed.
        const FORMAT_STRING =
            \\thoughts: {s}
            \\tool: {s}
            \\parameters: {s}
            \\observation: {s}
        ;
        return try std.fmt.allocPrint(allocator, FORMAT_STRING, .{
            step.thoughts,
            step.tool,
            step.parameters,
            step.observation.?,
        });
    }

    pub fn formatPrompt(self: *const ReactAgentTemplate, allocator: std.mem.Allocator, input: base.AgentInput, steps: []const InternalStep, tool_manager: tools.ToolManager) ![]const u8 {
        // For this AgentTemplate set, input should be a string (but doesn't have to be for other implementations)
        // Does this work?
        const step_string = try templ.formatSteps(allocator, steps, formatInternalStep);
        const p = try std.fmt.allocPrint(allocator, prompt, .{
            self.system_prompt,
            try tool_manager.describe(allocator), // arena allocator, how can I fix this?
            input.text,
            step_string,
        });
        return p;
    }

    pub fn parseOutput(_: *const ReactAgentTemplate, allocator: std.mem.Allocator, slice: []const u8) !InternalStep {
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

    pub fn template(self: *const ReactAgentTemplate) AgentTemplate {
        return AgentTemplate.init(self);
    }
};
