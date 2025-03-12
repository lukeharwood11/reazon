const std = @import("std");
const base = @import("base.zig");
const instructions = @import("instructions.zig");
const tools = @import("../tools/base.zig");

const InternalStep = base.InternalStep;

const ReactInstruction = struct {
    system_prompt: []const u8,

    const prompt =
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

    pub fn formatPrompt(self: *const ReactInstruction, allocator: std.mem.Allocator, input: anytype, steps: []const InternalStep, tool_manager: tools.ToolManager) ![]const u8 {
        // For this Instruction set, input should be a string (but doesn't have to be for other implementations)
        // Does this work?
        if (@TypeOf(input) != []const u8) {
            @compileError("Input is of type '" ++ @typeName(@TypeOf(input)) ++ "' but should be of type '[]const u8'.");
        }
        const step_string = instructions.formatSteps(allocator, steps);
        // segfault?
        defer allocator.free(step_string);
        const p = try std.fmt.allocPrint(allocator, prompt, .{
            self.system_prompt,
            try tool_manager.describe(allocator), // arena allocator, how can I fix this?
            input,
            step_string,
        });
        defer allocator.free(p);
        // TODO: handle this
    }

    pub fn parseOutput(_: *const ReactInstruction, allocator: std.mem.Allocator, slice: []const u8) !InternalStep {
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
};
