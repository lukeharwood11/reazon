const std = @import("std");
const proxz = @import("proxz");
const agentz = @import("agentz");

const Tool = agentz.tools.Tool;
const Agent = agentz.agents.Agent;

pub fn main() !void {
    const DebugAllocator = std.heap.DebugAllocator(.{});
    var gpa: DebugAllocator = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const weather_tool: Tool = .{
        .name = "get_weather",
        .description = "Get's weather for the given city",
        .params = &[_]Tool.Parameter{.{
            .name = "city",
            .dtype = .string,
            .description = "The city to search",
        }},
        .toolFn = struct {
            pub fn func(_: *const Tool, _: std.mem.Allocator, _: std.json.ObjectMap) ![]const u8 {
                return "53 and sunny - low chance of rain";
            }
        }.func,
    };

    const tools = &[_]Tool{
        weather_tool,
    };

    var agent = try Agent.init(allocator, .{
        .system_prompt = "You are a helpful agent.",
        .tools = tools,
    });
    defer agent.deinit();

    const response = try agent.execute("What is the weather in new berlin?");
    std.log.info("Main Output: {s}", .{response});
}
