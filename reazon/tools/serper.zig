const std = @import("std");
const base = @import("base.zig");

pub const SerperConfig = struct {};
pub const SerperClientError = error{ MemoryError, APIKeyNotSet };
const Tool = base.Tool;

pub const SerperTool = struct {
    arena: *std.heap.ArenaAllocator,
    headers: []const std.http.Header,

    pub fn init(allocator: std.mem.Allocator, config: SerperConfig) SerperClientError!*SerperTool {
        const arena = allocator.create(std.heap.ArenaAllocator) catch {
            return SerperClientError.MemoryError;
        };
        arena.* = std.heap.ArenaAllocator.init(allocator);

        errdefer blk: {
            arena.deinit();
            allocator.destroy(arena);
            break :blk;
        }

        // get env vars
        var env_map = std.process.getEnvMap(allocator) catch {
            return SerperClientError.MemoryError;
        };
        defer env_map.deinit();

        // make all strings managed on the heap via the arena allocator
        const api_key = try moveNullableString(arena.allocator(), config.api_key orelse env_map.get("SERPER_API_KEY")) orelse {
            return SerperClientError.APIKeyNotSet;
        };

        const headers: []const std.http.Header = &[_]std.http.Header{
            .{
                .name = "X-API-KEY",
                .value = api_key,
            },
            .{
                .name = "Content-Type",
                .value = "application/json",
            },
        };
        return .{
            .arena = arena,
            .headers = headers,
        };
    }

    fn search(_: *const SerperTool, _: *const Tool, _: std.mem.Allocator, _: std.json.ObjectMap) ![]const u8 {
        return "";
    }

    pub fn tool(self: *const SerperTool) Tool {
        return .{
            .name = "web_search",
            .description = "Useful for when you need to search the web",
            .params = &.{},
            .toolFn = self.search,
        };
    }

    pub fn deinit(self: *const SerperTool) void {
        self.arena.deinit();
        self.arena.child_allocator.destroy(self.arena);
    }

    fn moveNullableString(allocator: std.mem.Allocator, str: ?[]const u8) !?[]const u8 {
        if (str) |s| {
            return allocator.dupe(u8, s) catch {
                return SerperClientError.MemoryError;
            };
        } else {
            return null;
        }
    }
};
