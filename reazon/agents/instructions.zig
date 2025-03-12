const std = @import("std");
const base = @import("base.zig");

const InternalStep = base.InternalStep;

pub fn leakyFormatSteps(allocator: std.mem.Allocator, steps: []const InternalStep) []const u8 {
    var step_string: []const u8 = "";
    for (steps.items, 0..) |step, i| {
        step_string = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
            step_string,
            if (i == 0) "" else "\n",
            try step.formatPrompt(allocator),
        });
    }
    return step_string;
}

pub fn formatSteps(allocator: std.mem.Allocator, steps: []const InternalStep) []const u8 {
    var step_string: []const u8 = "";
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    for (steps.items, 0..) |step, i| {
        step_string = try std.fmt.allocPrint(arena.allocator(), "{s}{s}{s}", .{
            step_string,
            if (i == 0) "" else "\n",
            try step.formatPrompt(arena.allocator()),
        });
    }
    return allocator.dupe(u8, step_string);
}

// Thank you openmymind.net/Zig-Interfaces/
pub const Instruction = struct {
    // meta properties
    ptr: *const anyopaque,
    formatPromptFn: *const fn (ptr: *const anyopaque, input: anytype, steps: []const InternalStep) anyerror![]const u8,

    pub fn init(ptr: anytype) Instruction {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const fns = struct {
            pub fn formatPrompt(pointer: *const anyopaque, input: anytype, steps: []const InternalStep) anyerror![]const u8 {
                const self: T = @ptrCast(@alignCast(pointer));
                return ptr_info.pointer.child.formatPrompt(self, input, steps);
            }
        };
        return .{
            .ptr = ptr,
            .formatPromptFn = fns.formatPrompt,
        };
    }

    pub fn formatPrompt(self: *const Instruction, input: anytype, steps: []const InternalStep) anyerror![]const u8 {
        return self.formatPromptFn(self.ptr, input, steps);
    }

    pub fn parseOutput(self: *const Instruction, slice: []const u8) anyerror!InternalStep {
        _ = self;
        _ = slice;
    }
};
