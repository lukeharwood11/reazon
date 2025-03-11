const std = @import("std");
const base = @import("base.zig");

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

    pub fn formatPrompt(self: *const ReactInstruction, input: anytype, steps: []const InternalStep) ![]const u8 {
        _ = self;
        _ = input;
        _ = steps;
    }

    pub fn parseOutput(self: *const ReactInstruction, slice: []const u8) !InternalStep {
        _ = self;
        _ = slice;
    }
};
