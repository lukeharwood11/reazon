const std = @import("std");
const base = @import("base.zig");

const InternalStep = base.InternalStep;

// Thank you openmymind.net/Zig-Interfaces/
pub const Instruction = struct {
    ptr: *const anyopaque,
    formatPromptFn: *const fn (ptr: *const anyopaque, step: InternalStep) anyerror![]const u8,

    pub fn init(ptr: anytype) Instruction {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const fns = struct {
            pub fn formatPrompt(pointer: *const anyopaque, step: InternalStep) anyerror![]const u8 {
                const self: T = @ptrCast(@alignCast(pointer));
                return ptr_info.pointer.child.chat(self, step);
            }
        };
        return .{
            .ptr = ptr,
            .formatPromptFn = fns.formatPrompt,
        };
    }

    pub fn formatPrompt(self: *const Instruction, step: InternalStep) anyerror![]const u8 {
        return self.formatPromptFn(self.ptr, step);
    }
};
