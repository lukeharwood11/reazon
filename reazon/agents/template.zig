const std = @import("std");
const base = @import("base.zig");
const tools = @import("../tools/base.zig");

// exports
pub const ReactAgentTemplate = @import("react.zig").ReactAgentTemplate;
// - - - - - - - -

const InternalStep = base.InternalStep;
const ToolManager = tools.ToolManager;

pub fn leakyFormatSteps(allocator: std.mem.Allocator, steps: []const InternalStep, formatter: *const fn (step: InternalStep, allocator: std.mem.Allocator) anyerror![]const u8) ![]const u8 {
    var step_string: []const u8 = "";
    for (steps.items, 0..) |step, i| {
        step_string = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
            step_string,
            if (i == 0) "" else "\n",
            try formatter(step, allocator),
        });
    }
    return step_string;
}

/// Applies formatter over list of InternalStep elements
pub fn formatSteps(allocator: std.mem.Allocator, steps: []const InternalStep, formatter: *const fn (step: InternalStep, allocator: std.mem.Allocator) anyerror![]const u8) ![]const u8 {
    var step_string: []const u8 = "";
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    for (steps, 0..) |step, i| {
        step_string = try std.fmt.allocPrint(arena.allocator(), "{s}{s}{s}", .{
            step_string,
            if (i == 0) "" else "\n",
            try formatter(step, arena.allocator()),
        });
    }
    return allocator.dupe(u8, step_string);
}

// Thank you openmymind.net/Zig-Interfaces/
pub const AgentTemplate = struct {
    // meta properties
    ptr: *const anyopaque,

    formatPromptFn: *const fn (ptr: *const anyopaque, allocator: std.mem.Allocator, input: base.AgentInput, steps: []const InternalStep, tool_manager: ToolManager) anyerror![]const u8,
    parseOutputFn: *const fn (ptr: *const anyopaque, allocator: std.mem.Allocator, slice: []const u8) anyerror!InternalStep,

    pub fn init(ptr: anytype) AgentTemplate {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const fns = struct {
            pub fn formatPrompt(pointer: *const anyopaque, allocator: std.mem.Allocator, input: base.AgentInput, steps: []const InternalStep, tool_manager: ToolManager) anyerror![]const u8 {
                const self: T = @ptrCast(@alignCast(pointer));
                return ptr_info.pointer.child.formatPrompt(self, allocator, input, steps, tool_manager);
            }

            pub fn parseOutput(pointer: *const anyopaque, allocator: std.mem.Allocator, slice: []const u8) anyerror!InternalStep {
                const self: T = @ptrCast(@alignCast(pointer));
                return ptr_info.pointer.child.parseOutput(self, allocator, slice);
            }
        };
        return .{
            .ptr = ptr,
            .formatPromptFn = fns.formatPrompt,
            .parseOutputFn = fns.parseOutput,
        };
    }

    pub fn formatPrompt(self: *const AgentTemplate, allocator: std.mem.Allocator, input: base.AgentInput, steps: []const InternalStep, tool_manager: ToolManager) anyerror![]const u8 {
        return self.formatPromptFn(self.ptr, allocator, input, steps, tool_manager);
    }

    pub fn parseOutput(self: *const AgentTemplate, allocator: std.mem.Allocator, slice: []const u8) anyerror!InternalStep {
        return self.parseOutputFn(self.ptr, allocator, slice);
    }
};
