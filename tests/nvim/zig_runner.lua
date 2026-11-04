-- Preserve Zig's native leak/error-log failures and deterministic fuzz corpus.
require("lazy").load({ plugins = { "neotest" } })
local adapter = require("config.zig_test").adapter()
local nio = require("nio")
local root = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(vim.env.TMPDIR, "zig-runner-XXXXXX")))
local path = root .. "/semantics.zig"
vim.fn.writefile({
	'const std = @import("std");',
	"var calls: usize = 0;",
	"fn fuzzInput(_: void, _: *std.testing.Smith) !void { calls += 1; }",
	'test "leak" { _ = try std.testing.allocator.alloc(u8, 4); }',
	'test "logged" { std.log.err("expected negative control", .{}); }',
	'test "fuzz" {',
	"  calls = 0;",
	'  try std.testing.fuzz(@as(void, {}), fuzzInput, .{.corpus=&.{"abc"}});',
	"  try std.testing.expectEqual(@as(usize, 2), calls);",
	"}",
}, path)
local done, failure
nio.run(function()
	local ok, err = xpcall(function()
		local tree = assert(adapter.discover_positions(path))
		local spec = adapter.build_spec({ tree = tree })
		local process = spec.strategy(spec, { adapter = adapter, position = tree:data() })
		local code = process.result()
		assert(code ~= 0, "ZIG_NATIVE_FAILURES_IGNORED")
		local results = adapter.results(spec, { code = code }, tree)
		local expected = { ['"leak"'] = "failed", ['"logged"'] = "failed", ['"fuzz"'] = "passed" }
		for _, node in tree:iter_nodes() do
			local data = node:data()
			if data.type == "test" then
				assert(
					results[data.id].status == expected[data.name],
					"ZIG_RUNNER_NATIVE_SEMANTICS: " .. vim.inspect(results) .. " output=" .. spec.context.output
				)
			end
		end
	end, debug.traceback)
	failure, done = not ok and err or nil, true
end)
assert(
	vim.wait(120000, function()
		return done
	end, 20),
	"ZIG_RUNNER_TIMEOUT"
)
assert(not failure, failure)
io.stdout:write("ZIG_RUNNER_COMPLETE\n")
