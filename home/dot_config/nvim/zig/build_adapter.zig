//! Loaded through a unique, exclusively-owned helper beside the project's
//! build.zig. Keep the original graph for ordinary tests; DAP accepts only
//! native addRunArtifact test steps whose launch inputs can be preserved.
const std = @import("std");
const original = @import("build.zig");
const Launch = struct { program: []const u8, cwd: []const u8, args: []const []const u8, env: std.json.Value, output: []const u8 };

pub fn build(b: *std.Build) !void {
    const runner = b.option([]const u8, "dotfiles-runner", "Repository test runner") orelse return error.MissingRunner;
    const input = b.option([]const u8, "dotfiles-input", "Selected test identities") orelse return error.MissingInput;
    const artifacts = b.option([]const u8, "dotfiles-artifacts", "Owned result directory") orelse return error.MissingArtifacts;
    const debug = b.option(bool, "dotfiles-debug", "Build tests for codelldb") orelse false;
    if (@typeInfo(@typeInfo(@TypeOf(original.build)).@"fn".return_type.?) == .error_union) {
        try original.build(b);
    } else {
        original.build(b);
    }
    const top = b.top_level_steps.get("test") orelse return error.NoNativeTestStep;
    var seen: std.AutoHashMap(*std.Build.Step, void) = .init(b.allocator);
    var runs: std.ArrayList(*std.Build.Step.Run) = .empty;
    try collect(&top.step, &seen, &runs, b.allocator);
    if (runs.items.len == 0) return error.NoNativeTestArtifact;
    const debug_step = b.step("dotfiles-debug-tests", "Build selected native test artifacts without running them");
    var launches: std.ArrayList(Launch) = .empty;
    var replaced: std.AutoHashMap(*std.Build.Step.Compile, void) = .init(b.allocator);
    for (runs.items, 0..) |run, index| {
        const compile = run.producer.?;
        if (!replaced.contains(compile)) {
            if (compile.test_runner != null) return error.ProjectHasCustomTestRunnerUseNativeWorkflow;
            compile.test_runner = .{ .path = .{ .cwd_relative = runner }, .mode = .simple };
            try replaced.put(compile, {});
        }
        const output = b.fmt("{s}/result-{d}.json", .{ artifacts, index });
        if (!debug) {
            // addRunArtifact chose server mode before we replaced its runner.
            // Preserve its cwd, env, arguments and dependency graph unchanged.
            if (run.stdio != .check) {
                run.stdio = .{ .check = .empty };
                run.expectExitCode(0);
            }
            run.has_side_effects = true;
            run.addArgs(&.{ "--dotfiles-input", input, "--dotfiles-output", output });
            continue;
        }
        if ((compile.root_module.optimize orelse .debug) != .debug) return error.DebugTestsRequireDebugOptimization;
        // Extra top-level/Run prerequisites can have ordering or side effects
        // which a standalone debugger cannot faithfully replay.
        for (top.step.dependencies.items) |dependency| {
            const direct = dependency.cast(std.Build.Step.Run) orelse return error.DebugRequiresDirectNativeTestSteps;
            if (direct.producer == null or direct.producer.?.kind != .@"test") return error.DebugRequiresDirectNativeTestSteps;
        }
        for (run.step.dependencies.items) |dependency| {
            if (dependency != &compile.step) return error.DebugHasAdditionalRunPrerequisitesUseNativeWorkflow;
        }
        if (run.stdin != .none) return error.DebugStdinRequiresNativeWorkflow;
        var args: std.ArrayList([]const u8) = .empty;
        for (run.argv.items, 0..) |arg, arg_index| {
            if (arg_index == 0) {
                if (arg != .artifact or arg.artifact.artifact != compile or arg.artifact.prefix.len != 0 or arg.artifact.suffix.len != 0) return error.UnsupportedNativeTestCommand;
            } else {
                if (arg != .bytes) return error.DebugGeneratedArgumentsRequireNativeWorkflow;
                try args.append(b.allocator, arg.bytes);
            }
        }
        try args.appendSlice(b.allocator, &.{ "--dotfiles-input", input, "--dotfiles-output", output });
        var env: std.json.ObjectMap = .empty;
        if (run.environ_map) |map| {
            var inherited = b.graph.environ_map.iterator();
            while (inherited.next()) |entry| {
                if (!map.contains(entry.key_ptr.*)) return error.DebugUnsetEnvironmentRequiresNativeWorkflow;
            }
            var entries = map.iterator();
            while (entries.next()) |entry| try env.put(b.allocator, entry.key_ptr.*, .{ .string = entry.value_ptr.* });
        }
        const cwd = if (run.cwd) |path| switch (path) {
            .src_path => |p| try p.owner.root.joinString(b.allocator, p.sub_path),
            .cwd_relative => |p| try std.fs.path.resolve(b.allocator, &.{p}),
            else => return error.DebugGeneratedCwdRequiresNativeWorkflow,
        } else try b.root.joinString(b.allocator, "");
        const name = b.fmt("dotfiles-test-{d}", .{index});
        const install = b.addInstallArtifact(compile, .{ .dest_sub_path = name });
        debug_step.dependOn(&install.step);
        try launches.append(b.allocator, .{ .program = b.fmt("{s}/install/bin/{s}", .{ artifacts, name }), .cwd = cwd, .args = args.items, .env = .{ .object = env }, .output = output });
    }
    if (debug) {
        const json = try std.json.Stringify.valueAlloc(b.allocator, launches.items, .{});
        try std.Io.Dir.cwd().writeFile(b.graph.io, .{ .sub_path = b.fmt("{s}/launch.json", .{artifacts}), .data = json });
    }
}

fn collect(step: *std.Build.Step, seen: *std.AutoHashMap(*std.Build.Step, void), runs: *std.ArrayList(*std.Build.Step.Run), allocator: std.mem.Allocator) !void {
    if (seen.contains(step)) return;
    try seen.put(step, {});
    if (step.cast(std.Build.Step.Run)) |run| {
        if (run.producer) |producer| {
            if (producer.kind == .@"test") {
                try runs.append(allocator, run);
                return;
            }
        }
    }
    for (step.dependencies.items) |dependency| try collect(dependency, seen, runs, allocator);
}
