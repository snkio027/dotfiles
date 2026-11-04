//! Neotest's repository-owned Zig 0.17 runner. The pinned adapter's discovery
//! remains unchanged; native test allocation, I/O and leak checks are preserved.
const std = @import("std");
const builtin = @import("builtin");
const Input = struct { id: []const u8, name: []const u8, path: []const u8 };
const Result = struct { id: []const u8, status: []const u8, short: []const u8, line: ?u64 = null };
var error_logs: usize = 0;

pub const std_options: std.Options = .{ .logFn = log };
pub fn log(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    if (@backingInt(level) <= @backingInt(std.log.Level.err)) error_logs += 1;
    if (@backingInt(level) > @backingInt(std.testing.log_level)) return;
    std.debug.print("[" ++ @tagName(scope) ++ "] " ++ format ++ "\n", args);
}

// Preserve the default runner's deterministic corpus checks. Instrumented
// fuzz campaigns use Zig's native workflow, not this interactive test runner.
pub fn fuzz(context: anytype, comptime testOne: fn (@TypeOf(context), *std.testing.Smith) anyerror!void, options: std.testing.FuzzInputOptions) anyerror!void {
    if (builtin.fuzz) return error.UseNativeFuzzWorkflow;
    for (options.corpus) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try testOne(context, &smith);
    }
    var smith: std.testing.Smith = .{ .in = "" };
    try testOne(context, &smith);
}

pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    const gpa = arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(gpa);
    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--dotfiles-input") and i + 1 < args.len) {
            i += 1;
            input_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--dotfiles-output") and i + 1 < args.len) {
            i += 1;
            output_path = args[i];
        }
    }
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, input_path orelse return error.MissingInput, gpa, .limited(16 * 1024 * 1024));
    const parsed = try std.json.parseFromSlice([]Input, gpa, bytes, .{});
    const inputs = parsed.value;
    var results: std.ArrayList(Result) = .empty;
    var debug_info: std.debug.SelfInfo = .init;
    defer debug_info.deinit(io);
    var failed = false;

    for (builtin.test_functions) |test_fn| {
        var symbols: std.ArrayList(std.debug.Symbol) = .empty;
        try debug_info.getSymbols(io, gpa, gpa, @intFromPtr(test_fn.func), false, &symbols);
        var location: ?std.debug.SourceLocation = null;
        for (symbols.items) |symbol| {
            if (symbol.source_location) |loc| {
                location = loc;
                break;
            }
        }
        const loc = location orelse return error.MissingTestSourceLocation;
        const source = try std.fs.path.resolve(gpa, &.{loc.file_name});
        for (inputs) |input| {
            // The compiler prefixes test names with the declaring module. Source
            // identity disambiguates equal names in different project files.
            if (!std.mem.eql(u8, input.path, source)) continue;
            if (!std.mem.endsWith(u8, test_fn.name, input.name)) continue;
            const prefix_len = test_fn.name.len - input.name.len;
            if (prefix_len != 0 and test_fn.name[prefix_len - 1] != '.') continue;

            std.testing.allocator_instance = .init(std.heap.page_allocator, .{ .canary = 0xc3a701ba, .check_write_after_free = true });
            std.testing.io_instance = .init(std.testing.allocator, .{ .argv0 = .init(init.minimal.args), .environ = init.minimal.environ });
            std.testing.environ = init.minimal.environ;
            std.testing.log_level = .warn;
            error_logs = 0;
            var status: []const u8 = "passed";
            var message: []const u8 = "passed";
            test_fn.func() catch |err| {
                if (err == error.SkipZigTest) {
                    status = "skipped";
                    message = "SkipZigTest";
                } else {
                    status = "failed";
                    message = @errorName(err);
                    if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
                }
            };
            std.testing.io_instance.deinit();
            const leaks = std.testing.allocator_instance.deinit();
            if (leaks != 0 or error_logs != 0) {
                status = "failed";
                message = if (leaks != 0) "test leaked memory" else "test logged errors";
            }
            failed = failed or std.mem.eql(u8, status, "failed");
            try results.append(gpa, .{ .id = input.id, .status = status, .short = message, .line = loc.line });
            // Save each completed result. A later panic must not turn earlier
            // passing tests into missing results or fabricate success.
            const json = try std.json.Stringify.valueAlloc(gpa, results.items, .{});
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path orelse return error.MissingOutput, .data = json });
        }
    }
    if (results.items.len == 0) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path orelse return error.MissingOutput, .data = "[]" });
    }
    if (failed) std.process.exit(1);
}
