-- Rust discovery readiness boundary; native tree/build/results remain delegated.
local names = {
	"rustaceanvim.neotest",
	"rustaceanvim.rust_analyzer",
	"nio",
	"config.rust_clients",
	"neotest.client",
	"config.rust_neotest",
}
local saved = {}
for _, name in ipairs(names) do
	saved[name] = package.loaded[name]
end
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
fixture = assert(vim.uv.fs_realpath(fixture))
local file = fixture .. "/loaded.rs"
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, file)
local clock, sleeps, requests, discoveries = 0, 0, 0, 0
local hrtime = vim.uv.hrtime
vim.uv.hrtime = function()
	return clock
end
local current, readiness, response_error, response, native_error, on_sleep, on_schedule
local client = {
	id = 7,
	initialized = true,
	is_stopped = function()
		return false
	end,
	supports_method = function(_, method)
		return method == "experimental/runnables"
	end,
}
local native = {
	name = "rustaceanvim",
	root = function()
		return fixture
	end,
	build_spec = function()
		return "native-build"
	end,
	results = function()
		return "native-results"
	end,
	discover_positions = function(path)
		discoveries = discoveries + 1
		assert(path == file, "native discovery target changed")
		if native_error then
			error(native_error)
		end
		return "native-tree"
	end,
}
package.loaded["neotest.client"] = function()
	return {}
end
package.loaded["config.rust_neotest"] = nil
package.loaded["rustaceanvim.neotest"] = native
package.loaded["rustaceanvim.rust_analyzer"] = {
	get_client_for_file = function(path)
		assert(path == file or path == fixture .. "/unopened.rs", "unexpected discovery path")
		return current
	end,
}
package.loaded["config.rust_clients"] = {
	ready = function(candidate)
		assert(candidate == client)
		return readiness
	end,
}
package.loaded.nio = {
	scheduler = function()
		if on_schedule then
			on_schedule()
		end
	end,
	sleep = function(ms)
		sleeps = sleeps + 1
		clock = clock + ms * 1e6
		if on_sleep then
			on_sleep(sleeps)
		end
	end,
	lsp = {
		get_client_by_id = function(id)
			assert(id == client.id, "discovery used a different client")
			return {
				request = {
					experimental_runnables = function(params, request_buf, opts)
						requests = requests + 1
						assert(readiness, "runnable query was issued before quiescence")
						assert(params.textDocument.uri == vim.uri_from_fname(file), "preflight target changed")
						assert(request_buf == buf and opts.timeout == 100000, "native request policy changed")
						return response_error, response
					end,
				},
			}
		end,
	},
}
local ok, err = pcall(function()
	local adapter = require("config.rust_neotest").adapter()
	assert(
		adapter.build_spec == native.build_spec and adapter.results == native.results and adapter.root == native.root,
		"native Cargo/test/result implementations changed"
	)
	assert(
		adapter.discover_positions(fixture .. "/unopened.rs") == nil and sleeps == 0 and requests == 0,
		"unopened unrelated source started a discovery wait"
	)
	on_sleep = function(count)
		if count == 1 then
			current = client
		end
		if count == 3 then
			readiness = true
		end
	end
	response = { { label = "real runnable" } }
	assert(adapter.discover_positions(file) == "native-tree", "ready discovery did not delegate")
	assert(sleeps == 3 and requests == 1 and discoveries == 1, "startup readiness was not awaited once")
	on_sleep = nil
	response = {}
	assert(adapter.discover_positions(file) == nil and discoveries == 1, "empty native runnables were parsed as a tree")
	response_error = { message = "native request failure" }
	local request_ok, request_err = pcall(adapter.discover_positions, file)
	assert(
		not request_ok and tostring(request_err):find("native request failure", 1, true),
		"request error was swallowed"
	)
	response_error, response = nil, nil
	local invalid_ok, invalid_err = pcall(adapter.discover_positions, file)
	assert(
		not invalid_ok and tostring(invalid_err):find("invalid runnable list", 1, true),
		"invalid response was swallowed"
	)
	response, native_error = { { label = "real runnable" } }, "concurrent native failure"
	local native_ok, native_err = pcall(adapter.discover_positions, file)
	assert(
		not native_ok and tostring(native_err):find(native_error, 1, true),
		"native concurrent failure was swallowed"
	)
	native_error, readiness = nil, false
	local timeout_ok, timeout_err = pcall(adapter.discover_positions, file)
	assert(
		not timeout_ok and tostring(timeout_err):find("waiting for rust-analyzer", 1, true),
		"unready loaded file never stopped waiting"
	)
	assert(clock >= 30 * 1e9 and clock < 31 * 1e9, "startup wait changed its bound")
	-- A BufAdd discovery may begin before :edit loads the buffer/FileType.
	-- One scheduler turn reaches the actual startup; unopened files still skip.
	vim.api.nvim_buf_delete(buf, { force = true })
	current, readiness, native_error = nil, false, nil
	response = { { label = "real runnable" } }
	local before_sleeps, before_discoveries = sleeps, discoveries
	on_schedule = function()
		buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, file)
		current, readiness = client, true
	end
	assert(adapter.discover_positions(file) == "native-tree", "opening buffer skipped before scheduled FileType")
	assert(sleeps == before_sleeps and discoveries == before_discoveries + 1, "opening buffer introduced extra polling")
	on_schedule = nil
end)
vim.uv.hrtime = hrtime
for _, name in ipairs(names) do
	package.loaded[name] = saved[name]
end
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(fixture, "rf")
assert(ok, err)
print("RUST_NEOTEST_COMPLETE")
