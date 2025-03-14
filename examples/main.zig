const std = @import("std");
const proxz = @import("proxz");
const reazon = @import("reazon");

const Tool = reazon.tools.Tool;
const Agent = reazon.agents.Agent;
const ReactAgentTemplate = reazon.agents.templates.ReactAgentTemplate;
const ChatOpenAI = reazon.llm.openai.ChatOpenAI;
const SerperTool = reazon.tools.SerperTool;

pub const std_options = std.Options{
    .log_level = .debug, // this sets your app level log config
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{
            .scope = .proxz,
            .level = .err, // set to .debug, .warn, .info, or .err
        },
    },
};

pub fn main() !void {
    const DebugAllocator = std.heap.DebugAllocator(.{});
    var gpa: DebugAllocator = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // const weather_tool: Tool = .{
    //     .name = "get_weather",
    //     .description = "Get's weather for the given city",
    //     .params = &[_]Tool.Parameter{.{
    //         .name = "city",
    //         .dtype = .string,
    //         .description = "The city to search",
    //     }},
    //     .toolFn = struct {
    //         pub fn func(_: *const Tool, _: std.mem.Allocator, _: std.json.ObjectMap) ![]const u8 {
    //             return "53 and sunny - low chance of rain";
    //         }
    //     }.func,
    // };

    const weather_tool = Tool.fromStruct(struct {
        pub const params = &[_]Tool.Parameter{.{
            .name = "city",
            .dtype = .string,
            .description = "The city to search",
        }};
        pub const description = "Get's weather for the given city";
        // the name is used as the name of the function
        pub fn get_weather(_: *const Tool, _: std.mem.Allocator, _: std.json.ObjectMap) ![]const u8 {
            return "53 and sunny - low chance of rain";
        }
    });

    const serper = try SerperTool.init(allocator, .{});
    defer serper.deinit();

    const tools = &[_]Tool{
        weather_tool,
        serper.tool(),
    };

    const rat: ReactAgentTemplate = .default;

    const openai = try ChatOpenAI.init(
        allocator,
        .{
            .model = "gpt-4o-mini",
            .stop = ReactAgentTemplate.stop,
        },
    );
    defer openai.deinit();

    var agent = try Agent.init(allocator, .{
        .system_prompt = "You are a helpful agent.",
        .tools = tools,
        .llm = openai.llm(),
        .template = rat.template(),
    });
    defer agent.deinit();

    const response = try agent.execute("Check the internet for news.");
    std.log.info("\"{s}\"", .{response});
}
