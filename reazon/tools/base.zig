const std = @import("std");
const agents = @import("../agents/base.zig");

const InternalStep = agents.InternalStep;

// Note:
// 1. the first arg most likely needs to be of type Tool with anyopaque
// 2. a registered tool either needs to have access to the parent Agent, or it needs to have
// 3. should tools have a handle to the agent?
pub const Tool = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    params: []const Parameter = &.{},
    // change second parameter
    toolFn: *const fn (self: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) anyerror![]const u8,
    config: Config = .default,

    pub const Config = struct {
        exit: bool = false,
        pub const default: Config = .{};
    };

    pub fn fromStruct(comptime T: type) Tool {
        comptime var func_count = 0;
        comptime var tool_name: []const u8 = undefined;
        comptime var tool_description: ?[]const u8 = null;
        comptime var tool_params: []const Tool.Parameter = &.{};
        comptime var tool_fn: *const fn (self: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) anyerror![]const u8 = undefined;
        comptime var tool_config: Config = .default;
        // grab the tool fn
        const ti = @typeInfo(T);
        inline for (ti.@"struct".decls) |decl| {
            if (std.meta.hasMethod(T, decl.name)) {
                // handle methods
                func_count += 1;
                tool_fn = @field(T, decl.name);
                tool_name = decl.name;
            } else if (std.mem.eql(u8, decl.name, "params")) {
                // metadata.bodyType = @field(Handler, decl.name);
                tool_params = @field(T, "params");
            } else if (std.mem.eql(u8, decl.name, "description")) {
                // metadata.tags = @field(Handler, decl.name);
                tool_description = @field(T, "description");
            } else if (std.mem.eql(u8, decl.name, "config")) {
                tool_config = @field(T, "config");
            }
        }
        return .{
            .name = tool_name,
            .description = tool_description,
            .params = tool_params,
            .toolFn = tool_fn,
            .config = tool_config,
        };
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

        pub fn describe(self: *const Parameter, allocator: std.mem.Allocator) ![]const u8 {
            // TODO: add support for description?
            return try std.fmt.allocPrint(allocator, "{s}:{s}", .{
                self.name,
                std.enums.tagName(DataType, self.dtype).?, // compile error would occur
            });
        }
    };

    // should pass in an arena allocator
    pub fn describe(self: *const Tool, allocator: std.mem.Allocator) ![]const u8 {
        var arg_text: []const u8 = undefined;
        for (self.params, 0..) |arg, i| {
            const description = try arg.describe(allocator);
            if (i != 0) {
                arg_text = try std.fmt.allocPrint(allocator, "{s}, {s}", .{ arg_text, description });
            } else {
                arg_text = description;
            }
        }
        const tool_text = try std.fmt.allocPrint(allocator, "{s}({s})", .{
            self.name,
            arg_text,
        });
        return tool_text;
    }

    /// This is a runtime function, since it allows tools to be created dynamically
    pub fn validate(self: *const Tool) bool {
        // TODO:implement this
        return self.name.len > 0;
    }

    pub fn execute(self: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
        return try self.toolFn(self, allocator, params);
    }
};

pub const ToolManager = struct {
    // Note: refactor to use String type from zig-string or some equivalent (or make your own Luke:)
    // Maybe this should have a reference to the agent? And then the Tool has access to it's manager?
    tools: std.ArrayList(Tool),
    allocator: std.mem.Allocator,

    const return_tool: Tool = .{
        .name = "return",
        .description = "When you know the answer or can't find the answer.",
        .params = &[_]Tool.Parameter{
            .{
                .name = "text",
                .dtype = .string,
                .description = "The output to give to the user",
            },
        },
        // TODO: max the output of a function return a Signal, which includes whether an error occurred.
        .toolFn = struct {
            pub fn toolFn(_: *const Tool, _: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
                const output = params.get("text");
                if (output) |text| {
                    return text.string;
                }
                return "I didn't format my response properly, sorry :(";
            }
        }.toolFn,
        .config = .{ .exit = true },
    };

    pub fn init(allocator: std.mem.Allocator, tools: []const Tool) !ToolManager {
        var arr = std.ArrayList(Tool).init(allocator);
        // add all user defined tools
        try arr.appendSlice(tools);
        // allows the agent to exit and respond
        try arr.append(return_tool);
        return .{
            .tools = arr,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ToolManager) void {
        self.tools.deinit();
    }

    pub fn register(self: *ToolManager, tool: Tool) !void {
        try self.tools.append(tool);
    }

    pub fn registerMany(self: *ToolManager, tools: []Tool) !void {
        try self.tools.appendSlice(tools);
    }

    pub const ToolOutput = struct {
        exit: bool = false,
        content: []const u8,
    };

    // should pass in an arena allocator
    pub fn describe(self: *const ToolManager, allocator: std.mem.Allocator) ![]const u8 {
        var tool_text: []const u8 = undefined;
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        for (self.tools.items, 0..) |tool, i| {
            const description = try tool.describe(alloc);
            if (i != 0) {
                tool_text = try std.fmt.allocPrint(alloc, "{s}, {s}", .{ tool_text, description });
            } else {
                tool_text = description;
            }
        }
        return allocator.dupe(u8, tool_text);
    }

    pub fn execute(self: *const ToolManager, allocator: std.mem.Allocator, step: InternalStep) !ToolOutput {
        const parameters = std.json.parseFromSliceLeaky(
            std.json.Value,
            allocator,
            step.parameters,
            .{},
        ) catch {
            return .{ .content = "Failed to parse parameters." };
        };
        // TODO: error catch
        for (self.tools.items) |tool| {
            if (std.mem.eql(u8, tool.name, step.tool)) {
                const tool_output = tool.execute(allocator, parameters.object) catch {
                    return .{ .content = "Error when running tool." };
                };
                return .{
                    .exit = tool.config.exit,
                    .content = tool_output,
                };
            }
        }
        return .{ .content = "Error: no tool found with that name." };
    }
};
