-- Use the pinned native Neotest setup/consumer proxy with a fixture client.
local native_init = vim.api.nvim_get_runtime_file("lua/neotest/init.lua", false)[1]
if not native_init then
	require("neotest")
	native_init = assert(vim.api.nvim_get_runtime_file("lua/neotest/init.lua", false)[1])
end
local names = {
	"neotest.client",
	"neotest.config",
	"neotest.adapters",
	"neotest.consumers",
	"neotest.lib",
	"nio",
	"config.rust_neotest",
}
local saved = {}
for _, name in ipairs(names) do
	saved[name] = package.loaded[name]
end
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
fixture = assert(vim.uv.fs_realpath(fixture))
local a, b, nested = fixture .. "/app", fixture .. "/application", fixture .. "/app/nested"
for _, root in ipairs({ a, b, nested }) do
	vim.fn.mkdir(root .. "/src", "p")
	vim.fn.writefile({ "[package]" }, root .. "/Cargo.toml")
	vim.fn.writefile({ "#[test] fn sample() {}" }, root .. "/src/lib.rs")
end
assert(vim.uv.fs_symlink(b, fixture .. "/alias-b"))
local adapter, python = { name = "rustaceanvim" }, { name = "neotest-python" }
local aid, bid, nid = "rustaceanvim:" .. a, "rustaceanvim:" .. b, "rustaceanvim:" .. nested
local function node(path, kind, parsed)
	return {
		data = function()
			return {
				id = path,
				path = path,
				type = kind,
				range = parsed and { 0, 0, 5, 0 } or nil,
				runnable = parsed and { fixture = true } or nil,
			}
		end,
		children = function()
			return {}
		end,
	}
end
local trees = { [aid] = node(a, "dir") }
local positions = {
	[aid] = {
		[a .. "/src/lib.rs"] = node(a .. "/src/lib.rs", "file"),
		[nested .. "/src/lib.rs"] = node(nested .. "/src/lib.rs", "file"),
	},
}
local native_calls, resolver_calls, registrations, refreshes, runs = {}, {}, {}, {}, {}
local discovery_result = "parsed"
local group = {}
function group:adapters_with_root_dir(dir)
	assert(not dir:find("::", 1, true), "opaque test id reached filesystem resolver")
	dir = vim.uv.fs_realpath(dir) or vim.fs.normalize(dir)
	resolver_calls[#resolver_calls + 1] = dir
	local target
	for _, root in ipairs({ nested, b, a }) do
		if dir == root or dir:sub(1, #root + 1) == root .. "/" then
			target = root
			break
		end
	end
	return target and { { adapter = adapter, root = target } } or {}
end
local client = {
	_started = true,
	_adapters = { [aid] = adapter, python = python },
	_adapter_group = group,
	listeners = {},
	_state = {
		positions = function(_, id, position)
			return position and positions[id] and positions[id][position] or (position == nil and trees[id]) or nil
		end,
	},
	_get_adapter = function(self, position, id)
		native_calls[#native_calls + 1] = { position = position, id = id }
		if id and self._adapters[id] then
			return id, self._adapters[id]
		end
		return "native", python
	end,
	get_position = function(self, path, args)
		local id = self:_get_adapter(path, args and args.adapter)
		return self._state:positions(id, path), id
	end,
	run_tree = function(self, tree, args)
		runs[#runs + 1] =
			{ tree = tree, args = args, adapter = self:_get_adapter(tree:data().id, args and args.adapter) }
	end,
	_update_positions = function(_, path, args)
		refreshes[#refreshes + 1] = { path = path, adapter = args.adapter }
		coroutine.yield("native-discovery-await")
		if discovery_result == "parsed" then
			positions[args.adapter][path] = node(path, "file", true)
		end
	end,
	get_adapter = function(self, position, id)
		return self:_get_adapter(position, id)
	end,
	_update_adapters = function(self, dir)
		registrations[#registrations + 1] = dir
		coroutine.yield("native-registration-await")
		for _, entry in ipairs(group:adapters_with_root_dir(dir)) do
			local id = entry.adapter.name .. ":" .. entry.root
			self._adapters[id] = entry.adapter
			trees[id] = node(entry.root, "dir")
			positions[id] = { [entry.root .. "/src/lib.rs"] = node(entry.root .. "/src/lib.rs", "file") }
		end
	end,
}
local factory_calls, proxy = 0, nil
package.loaded["neotest.client"] = function(adapter_group)
	assert(adapter_group == group)
	factory_calls = factory_calls + 1
	return client
end
package.loaded["neotest.config"] = { setup = function() end, consumers = {}, run = { enabled = true } }
package.loaded["neotest.adapters"] = function()
	return group
end
package.loaded["neotest.lib"] = {
	files = { path = { real = vim.uv.fs_realpath } },
	notify = function(message)
		error(message)
	end,
}
package.loaded.nio = {
	create = function(fn)
		return fn
	end,
	run = function(fn)
		return fn()
	end,
	scheduler = function() end,
}
package.loaded["neotest.consumers"] = {
	run = assert(loadfile((native_init:gsub("init.lua$", "consumers/run.lua"))))(),
	probe = function(consumer)
		proxy = consumer
		return {
			lookup = function(path, id)
				return consumer:get_adapter(path, id)
			end,
		}
	end,
}
package.loaded["config.rust_neotest"] = nil
local scope = require("config.rust_neotest")
local instance
local function lookup(path, explicit)
	local thread = coroutine.create(function()
		return instance.probe.lookup(path, explicit)
	end)
	local ok, value, result = coroutine.resume(thread)
	assert(ok, value)
	if coroutine.status(thread) ~= "dead" then
		assert(value == "native-registration-await", "native async registration was not retained")
		assert(
			client._adapters[aid] == adapter and client._adapters.python == python,
			"shared registry hidden during await"
		)
		assert(
			instance.probe.lookup(fixture .. "/plain.py") == "native",
			"unrelated adapter hidden during Rust registration"
		)
		ok, value, result = coroutine.resume(thread)
		assert(ok, value)
	end
	assert(coroutine.status(thread) == "dead")
	return value, result
end
local ok, err = pcall(function()
	scope.install_routing()
	local factory = package.loaded["neotest.client"]
	scope.install_routing()
	assert(factory == package.loaded["neotest.client"], "factory install was not idempotent")
	instance = assert(loadfile(native_init))()
	instance.setup({})
	assert(factory_calls == 1 and proxy ~= client, "native setup did not create a real proxy through wrapped factory")
	-- This is why modifying a consumer cannot implement the production boundary.
	proxy._get_adapter = function()
		return "proxy-only-override"
	end
	assert(lookup(a .. "/src/lib.rs", "explicit-user-choice") == "native", "explicit adapter was overridden")
	assert(native_calls[#native_calls].id == "explicit-user-choice")
	assert(lookup(fixture .. "/plain.py") == "native", "non-Rust adapter lookup changed")
	local id, selected = lookup(b .. "/src/lib.rs")
	assert(id == bid and selected == adapter, "sibling prefix chose the parent Rust registry")
	assert(#registrations == 1, "new target did not use native registration")
	trees[bid] = node(b .. "/src", "dir")
	assert(lookup(b .. "/src/lib.rs") == bid, "discovered subtree replaced immutable registry root")
	assert(#registrations == 1, "partial position tree caused duplicate registration")
	assert(lookup(b) == bid and lookup(b .. "/src") == bid, "directory scope lost native workspace")
	assert(lookup(fixture .. "/alias-b/src/lib.rs") == bid, "canonical alias selected another registry")
	assert(positions[aid][nested .. "/src/lib.rs"], "nested cached-file fixture missing")
	assert(lookup(nested .. "/src/lib.rs") == nid, "nested cached file bypassed native workspace resolution")
	assert(#registrations == 2, "nested workspace not registered natively")
	assert(lookup(a .. "/src/lib.rs") == aid, "nested registry replaced parent")

	local test_id, namespace_id = nested .. "/src/lib.rs::module::sample", nested .. "/src/lib.rs::module"
	positions[nid][test_id] = node(nested .. "/src/lib.rs", "test")
	positions[nid][namespace_id] = node(nested .. "/src/lib.rs", "namespace")
	positions[aid][test_id] = positions[nid][test_id]
	local before = #resolver_calls
	assert(lookup(test_id) == nid and lookup(namespace_id) == nid, "RunLast/namespace selected wrong registry")
	assert(#resolver_calls == before, "opaque test ID was parsed as a filesystem path")
	assert(lookup(nested .. "/src/lib.rs::unknown") == nid, "unknown test ID confused file and directory")
	assert(lookup(test_id, aid) == aid, "explicit RunLast adapter was overridden")
	assert(lookup(fixture .. "/unopened.rs") == "native", "unresolved Rust target changed native fallback")
	assert(client._adapters[aid] == adapter and client._adapters[bid] == adapter and client._adapters[nid] == adapter)
	local file = b .. "/src/lib.rs"
	local fallback = bid .. "/src"
	client._adapters[fallback] = adapter
	positions[fallback] = { [file] = node(file, "file", true) }
	trees[fallback] = node(b .. "/src", "dir")
	local function public_run(args, expected_adapter)
		local old_runs = #runs
		local thread = coroutine.create(function()
			instance.run.run(args)
		end)
		local resumed, state = coroutine.resume(thread)
		assert(resumed, state)
		assert(state == "native-discovery-await", "public file run did not await authoritative discovery")
		assert(#runs == old_runs, "placeholder was executed before native discovery finished")
		assert(
			refreshes[#refreshes].adapter == expected_adapter and refreshes[#refreshes].path == file,
			"discovery changed explicit/native registry identity"
		)
		resumed, state = coroutine.resume(thread)
		assert(resumed, state)
		assert(coroutine.status(thread) == "dead" and #runs == old_runs + 1)
		assert(
			runs[#runs].tree:data().runnable and runs[#runs].adapter == expected_adapter,
			"public run executed fallback or placeholder tree"
		)
	end
	assert(
		client:get_position(file):data().runnable == nil and #refreshes == 0,
		"viewing positions triggered discovery"
	)
	public_run(file, bid)
	local before_refreshes = #refreshes
	instance.run.run(file)
	assert(#refreshes == before_refreshes, "parsed file was rediscovered on each run")
	positions[fallback][file] = node(file, "file")
	public_run({ file, adapter = fallback }, fallback)
	assert(runs[#runs].args.adapter == fallback, "user adapter argument was replaced")
	positions[fallback][file] = node(file, "file")
	local thread = coroutine.create(function()
		instance.run.run_last()
	end)
	local resumed, state = coroutine.resume(thread)
	assert(resumed and state == "native-discovery-await", "RunLast skipped readiness for its stored exact adapter")
	assert(refreshes[#refreshes].adapter == fallback, "RunLast changed stored adapter")
	assert(coroutine.resume(thread) and coroutine.status(thread) == "dead")
	assert(runs[#runs].tree:data().runnable and runs[#runs].adapter == fallback)
	-- Native discovery catches errors in its own xpcall and leaves the directory
	-- placeholder unchanged. A real empty file likewise has no discovered tree.
	-- Both must stop this explicit run instead of reporting a zero-test run.
	local function no_discovered_tests(path)
		positions[bid][path] = node(path, "file")
		discovery_result = "none"
		local old_runs, old_refreshes = #runs, #refreshes
		local pending = coroutine.create(function()
			instance.run.run(path)
		end)
		local started, waiting = coroutine.resume(pending)
		assert(started and waiting == "native-discovery-await", "missing-tree run skipped native discovery")
		local completed, failure = coroutine.resume(pending)
		assert(
			not completed and tostring(failure):find("Rust test discovery produced no parsed tests for:", 1, true),
			"missing discovery result was executed as a successful placeholder"
		)
		assert(#runs == old_runs and #refreshes == old_refreshes + 1, "missing discovery ran or retried")
		assert(refreshes[#refreshes].adapter == bid, "missing discovery escaped the authoritative registry")
	end
	no_discovered_tests(file)
	local empty_file = b .. "/src/no_tests.rs"
	vim.fn.writefile({ "pub fn ordinary_function() {}" }, empty_file)
	no_discovered_tests(empty_file)
	discovery_result = "parsed"
	local final_refreshes = #refreshes
	client:run_tree(node(fixture .. "/plain.py", "file"), { adapter = "python" })
	client:run_tree(node(file .. "::opaque", "test"), {})
	client:run_tree(node(b, "dir"), {})
	assert(#refreshes == final_refreshes, "non-Rust/opaque/directory run entered file readiness")
end)
for _, name in ipairs(names) do
	package.loaded[name] = saved[name]
end
vim.fn.delete(fixture, "rf")
assert(ok, err)
print("RUST_SCOPE_COMPLETE")
