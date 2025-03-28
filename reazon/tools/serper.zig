const std = @import("std");
const base = @import("base.zig");
const log = std.log.scoped(.serper);

pub const SerperClientError = error{ MemoryError, APIKeyNotSet };
const Tool = base.Tool;

const initial_retry_delay = 0.5;
const max_retry_delay = 8;
const ArrayList = std.ArrayListUnmanaged;

pub const SerperResponse = struct {
    searchParameters: SearchParameters,
    knowledgeGraph: ?KnowledgeGraph = null,
    organic: []OrganicResult,
    peopleAlsoAsk: ?[]PeopleAlsoAsk = null,
    relatedSearches: ?[]RelatedSearch = null,
    places: ?[]Place = null,
    credits: ?u32 = null,
};

pub const SearchParameters = struct {
    q: []const u8,
    gl: ?[]const u8 = null,
    hl: ?[]const u8 = null,
    autocorrect: ?bool = null,
    page: ?u32 = null,
    // For responses using a different search engine, "engine" is optional.
    engine: ?[]const u8 = null,
    type: ?[]const u8 = null,
};

// TODO: probably should make this a std.json.Value (since the contract isn't clear)
pub const KnowledgeGraph = struct {
    title: []const u8,
    // Using the field name "type" is allowed here as a struct member.
    type: ?[]const u8 = null,
    website: ?[]const u8 = null,
    imageUrl: []const u8,
    description: []const u8,
    descriptionSource: ?[]const u8 = null,
    descriptionLink: ?[]const u8 = null,
    // Attributes is a hash map represented as a std.json.Value.
    attributes: ?std.json.Value = null,
};

pub const OrganicResult = struct {
    title: []const u8,
    link: []const u8,
    snippet: []const u8,
    position: u32,
    // Sitelinks are optional.
    sitelinks: ?[]Sitelink = null,
    // Attributes are optional and represented as a std.json.Value.
    attributes: ?std.json.Value = null,
    // Date is optional.
    date: ?[]const u8 = null,
};

pub const Sitelink = struct {
    title: []const u8,
    link: []const u8,
};

pub const PeopleAlsoAsk = struct {
    question: []const u8,
    snippet: ?[]const u8 = null,
    title: ?[]const u8 = null,
    link: ?[]const u8 = null,
};

pub const RelatedSearch = struct {
    query: []const u8,
};

pub const Place = struct {
    title: ?[]const u8 = null,
    address: ?[]const u8 = null,
    // Ratings are represented as floating-point values.
    rating: ?f64 = null,
    ratingCount: ?u32 = null,
    cid: ?[]const u8 = null,
};

pub const SerperConfig = struct {
    max_retries: usize = 3,
    api_key: ?[]const u8 = null,
};
pub const SerperTool = struct {
    arena: *std.heap.ArenaAllocator,
    headers: []const std.http.Header,
    config: SerperConfig,

    pub fn init(allocator: std.mem.Allocator, config: SerperConfig) SerperClientError!SerperTool {
        const arena = allocator.create(std.heap.ArenaAllocator) catch {
            return SerperClientError.MemoryError;
        };
        arena.* = std.heap.ArenaAllocator.init(allocator);

        errdefer {
            arena.deinit();
            allocator.destroy(arena);
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

        const headers = arena.allocator().alloc(std.http.Header, 2) catch {
            return SerperClientError.MemoryError;
        };

        headers[0] = .{
            .name = "X-API-KEY",
            .value = api_key,
        };
        headers[1] = .{
            .name = "Content-Type",
            .value = "application/json",
        };

        return .{
            .arena = arena,
            .headers = headers,
            .config = config,
        };
    }

    fn search(
        self: *const SerperTool,
        _: *const Tool,
        allocator: std.mem.Allocator,
        params: std.json.ObjectMap,
    ) ![]const u8 {
        const query = params.get("query") orelse return "Error: Missing 'query' parameter.";

        const uri = try std.Uri.parse("https://google.serper.dev/search");

        const server_header_buffer = try allocator.alloc(u8, 8 * 1024 * 4);
        defer allocator.free(server_header_buffer);

        // Create a new client for each request to avoid connection pool issues
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();
        var backoff: f32 = initial_retry_delay;

        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        const body = try std.json.stringifyAlloc(
            allocator,
            .{
                .q = query,
            },
            .{},
        );
        defer allocator.free(body);

        for (0..self.config.max_retries + 1) |attempt| {
            const res = try client.fetch(.{
                .server_header_buffer = server_header_buffer,
                .response_storage = .{
                    .dynamic = &response,
                },
                .location = .{ .uri = uri },
                .method = .POST,
                .payload = body,
                .extra_headers = self.headers,
            });

            const status = res.status;

            const status_int = @intFromEnum(status);
            log.info("POST - https://google.serper.dev/search - {d} {s}", .{ status_int, status.phrase() orelse "Unknown" });
            if (status_int < 200 or status_int >= 300) {
                if (attempt != self.config.max_retries and @intFromEnum(status) >= 429) {
                    // retry on 429, 500, and 503
                    log.info("Retrying ({d}/{d}) after {d} seconds.", .{ attempt + 1, self.config.max_retries, backoff });
                    std.time.sleep(@as(u64, @intFromFloat(backoff * std.time.ns_per_s)));
                    backoff = if (backoff * 2 <= max_retry_delay) backoff * 2 else max_retry_delay;
                }
                return "Error from API.";
            } else {
                const response_body = try std.json.parseFromSliceLeaky(SerperResponse, allocator, response.items, .{
                    .ignore_unknown_fields = true,
                    .allocate = .alloc_always, // get the memory away from the response var
                });

                var summary: []const u8 = "";
                if (response_body.knowledgeGraph) |graph| {
                    summary = try std.fmt.allocPrint(allocator, "{s}{s}", .{ graph.description, "\n" });
                }
                for (response_body.organic, 0..) |result, i| {
                    if (i == 3) break;
                    summary = try std.fmt.allocPrint(allocator, "{s}===Title: {s}\nLink:{s}\n{s}\n==={s}", .{
                        summary,
                        result.title,
                        result.link,
                        result.snippet,
                        if (i == 2) "" else "\n",
                    });
                }
                return summary;
            }
        }
        // max_retries must be >= 0 (since it's usize) and loop condition is 0..max_retries+1
        unreachable;
    }

    pub fn tool(self: *const SerperTool) Tool {
        const x = struct {
            // I suppose this is a sort of interface? kinda hate this, but it works.
            var this: *const SerperTool = undefined;
            pub fn func(t: *const Tool, allocator: std.mem.Allocator, params: std.json.ObjectMap) ![]const u8 {
                return search(this, t, allocator, params);
            }
        };
        x.this = self;
        return .{
            .name = "web_search",
            .description = "Useful for when you need to search the web",
            .params = &.{
                .{
                    .name = "query",
                    .dtype = .string,
                },
            },
            .toolFn = x.func,
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
