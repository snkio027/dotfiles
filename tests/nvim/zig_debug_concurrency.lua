-- Two requests queued before a scheduler tick must not both reserve test DAP.
-- Real adapter/lifecycle, with a held compile process as a deterministic barrier.
require("lazy").load({ plugins = { "neotest", "nvim-dap" } })
local nio = require("nio")
local adapter = require("config.zig_test").adapter()
local root = assert(vim.uv.fs_mkdtemp(vim.env.TMPDIR .. "/zig-dap-race-XXXXXX"))
local path = root .. "/probe.zig"
vim.fn.writefile({ 'test "probe" {}' }, path)
local position = { id = path .. '::"probe"', type = "test", name = '"probe"', path = path }
local tree = {
	data = function()
		return position
	end,
}
function tree:iter_nodes()
	local pending = true
	return function()
		if pending then
			pending = false
			return position.id, tree
		end
	end
end
local specs, built, failure = {}, false, nil
nio.run(function()
	local ok, err = xpcall(function()
		specs[1] = adapter.build_spec({ tree = tree, strategy = "dap" })
		specs[2] = adapter.build_spec({ tree = tree, strategy = "dap" })
	end, debug.traceback)
	failure, built = not ok and err or nil, true
end)
assert(
	vim.wait(5000, function()
		return built
	end, 10),
	"could not prepare concurrent Zig specs"
)
assert(not failure, failure)
local key = "neotest.client.strategies.integrated"
local integrated = package.loaded[key]
local launches, processes = {}, {}
package.loaded[key] = function()
	local done = nio.control.future()
	local output = root .. "/compile-" .. (#launches + 1) .. ".log"
	vim.fn.writefile({ "controlled compile barrier" }, output)
	local process = {
		result = function()
			done.wait()
			return 143
		end,
		output = function()
			return output
		end,
		stop = function()
			if not done.is_set() then
				done.set()
			end
		end,
		attach = function() end,
	}
	launches[#launches + 1] = process
	return process
end
local ok, err = xpcall(function()
	for index, spec in ipairs(specs) do
		processes[index] = spec.strategy(spec, { adapter = adapter, position = position })
	end
	assert(
		vim.wait(5000, function()
			return processes[2].is_complete() or #launches == 2
		end, 10),
		"concurrent Zig requests did not pass their scheduler boundary"
	)
	assert(#launches == 1, "two concurrent Zig debug requests both reached compilation")
	assert(processes[2].is_complete(), "conflicting Zig debug request was not rejected")
	assert(
		tostring(specs[2].context.error):find("Another Zig test debugger is active", 1, true),
		"missing concurrency explanation"
	)
	processes[1].stop()
	assert(
		vim.wait(5000, function()
			return processes[1].is_complete()
		end, 10),
		"first debug cancellation did not finish"
	)
	-- Rejection/cancellation releases the gate; another explicit request works.
	local again = specs[1].strategy(specs[1], { adapter = adapter, position = position })
	processes[#processes + 1] = again
	assert(
		vim.wait(5000, function()
			return #launches == 2
		end, 10),
		"cancelled debugger reservation was not released"
	)
	again.stop()
	assert(vim.wait(5000, again.is_complete, 10), "last controlled request did not finish")
	print("ZIG_DEBUG_CONCURRENCY_COMPLETE")
end, debug.traceback)
for _, process in ipairs(processes) do
	process.stop()
end
vim.wait(1000, function()
	for _, process in ipairs(processes) do
		if not process.is_complete() then
			return false
		end
	end
	return true
end, 10)
package.loaded[key] = integrated
assert(ok, err)
