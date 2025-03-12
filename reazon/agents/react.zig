const std = @import("std");
const base = @import("base.zig");
const instructions = @import("instructions.zig");

const InternalStep = base.InternalStep;

const ReactInstruction = struct {
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

    pub fn formatPrompt(self: *const ReactInstruction, allocator: std.mem.Allocator, input: anytype, steps: []const InternalStep) ![]const u8 {
        const step_string = instructions.formatSteps(allocator, steps);
        // segfault?
        defer allocator.free(step_string);
        const p = try std.fmt.allocPrint(allocator, prompt, .{
            self.config.system_prompt,
            try self.tool_manager.describe(allocator), // arena allocator
            input,
            step_string,
        });
        defer allocator.free(p);
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
