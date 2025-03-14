const std = @import("std");
const base = @import("base.zig");

pub const SerperClientError = error{ MemoryError, APIKeyNotSet };
const Tool = base.Tool;

const initial_retry_delay = 0.5;
const max_retry_delay = 8;
const ArrayList = std.ArrayListUnmanaged;

const log = std.log.scoped(.reazon);

pub const SerperConfig = struct {
    max_retries: usize = 3,
    api_key: ?[]const u8 = null,
};
pub const SerperTool = struct {
    arena: *std.heap.ArenaAllocator,
    headers: []const std.http.Header,

    pub fn init(allocator: std.mem.Allocator, config: SerperConfig) SerperClientError!SerperTool {
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

    fn search(self: *const SerperTool, _: *const Tool, allocator: std.mem.Allocator, _: std.json.ObjectMap) ![]const u8 {
        const uri = try std.Uri.parse("https://google.serper.dev/search");

        const server_header_buffer = try allocator.alloc(u8, 8 * 1024 * 4);
        defer allocator.free(server_header_buffer);

        // Create a new client for each request to avoid connection pool issues
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();
        var backoff: f32 = initial_retry_delay;

        const response = ArrayList(u8);
        defer response.deinit();

        for (0..self.max_retries + 1) |attempt| {
            const res = try client.fetch(.{
                .server_header_buffer = server_header_buffer,
                .response_storage = .{
                    .dynamic = response,
                },
                .location = .{ .uri = uri },
                .method = .POST,
                .payload = "{{ \"q\": \"apple inc\"}}",
                .privileged_headers = self.headers,
            });

            const status = res.status;

            const status_int = @intFromEnum(status);
            log.info("POST - https://google.serper.dev/search - {d} {s}", .{ status_int, status.phrase() orelse "Unknown" });
            if (status_int < 200 or status_int >= 300) {
                if (attempt != self.max_retries and @intFromEnum(status) >= 429) {
                    // retry on 429, 500, and 503
                    log.info("Retrying ({d}/{d}) after {d} seconds.", .{ attempt + 1, self.max_retries, backoff });
                    std.time.sleep(@as(u64, @intFromFloat(backoff * std.time.ns_per_s)));
                    backoff = if (backoff * 2 <= max_retry_delay) backoff * 2 else max_retry_delay;
                } else {
                    // const err = json.deserializeStructWithArena(APIErrorResponse, allocator, body) catch {
                    //     log.err("{s}", .{body});
                    //     // if we can't parse the error, it was a bad request.
                    //     return OpenAIError.BadRequest;
                    // };
                    // defer err.deinit();
                    // log.info("{s} ({s}): {s}", .{ err.@"error".type, err.@"error".code orelse "None", err.@"error".message });
                    // return getErrorFromStatus(status);
                }
                return "You got no results...";
            } else {
                // if (ResponseType) |T| {
                //     const response: T = try json.deserializeStructWithArena(T, allocator, body);
                //     return response;
                // } else {
                //     return;
                // }
                log.info("{s}", .{response.items});
                return "This worked!";
            }
        }
        // max_retries must be >= 0 (since it's usize) and loop condition is 0..max_retries+1
        unreachable;
    }

    pub fn tool(self: *const SerperTool) Tool {
        return .{ .name = "web_search", .description = "Useful for when you need to search the web", .params = &.{}, .toolFn = struct {
            pub fn func(t: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
                return search(self, t, allocator, params);
            }
        }.func };
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
