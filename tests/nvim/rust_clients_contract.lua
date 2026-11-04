-- Exercise asynchronous native-start boundaries without starting an LSP or Cargo.
local names = {
	"rustaceanvim.lsp",
	"rustaceanvim.cargo",
	"rustaceanvim.rust_analyzer",
	"rustaceanvim.server_status",
	"config.rust_clients",
}
local saved = {}
for _, name in ipairs(names) do
	saved[name] = package.loaded[name]
end
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture .. "/a", "p")
vim.fn.mkdir(fixture .. "/b", "p")
fixture = assert(vim.uv.fs_realpath(fixture))
assert(vim.uv.fs_symlink(fixture .. "/a", fixture .. "/alias-a"))
local a, b = fixture .. "/a", fixture .. "/b"
local clients = {
	{ id = 1, config = { root_dir = a } },
	{ id = 2, config = { root_dir = b } },
	{ id = 3, config = { root_dir = fixture .. "/other" } },
}
local calls, pending, observed = {}, {}, {}
local analyzer = {}
local native_clients = function(buf, filter)
	calls[#calls + 1] = { buf = buf, filter = filter }
	if filter and filter.method == "specific" then
		return { clients[1] }
	end
	return clients
end
analyzer.get_active_rustaceanvim_clients = native_clients
local metadata = {
	[1] = { root = a, filename = a .. "/main.rs" },
	[2] = { root = b, filename = b .. "/main.rs" },
	[3] = { root = fixture .. "/alias-a", filename = fixture .. "/alias-a/main.rs" },
	[4] = { root = nil, filename = a .. "/detached.rs" },
}
local cargo = {}
local native_resolve = function(config, filename, callback)
	assert(filename == config.filename, "native filename changed")
	if not callback then
		return config.root, "sync-result"
	end
	if config.sync then
		return callback(config.root)
	end
	pending[#pending + 1] = function()
		return callback(config.root)
	end
end
cargo.get_config_root_dir = native_resolve
local lsp = {}
local function ids()
	return vim.tbl_map(function(client)
		return client.id
	end, analyzer.get_active_rustaceanvim_clients())
end
lsp.start = function(buf)
	local config = assert(metadata[buf])
	if config.start_error then
		error("native start failure")
	end
	return cargo.get_config_root_dir(config, config.filename, function(root)
		observed[#observed + 1] = { buf = buf, ids = ids() }
		assert(
			#analyzer.get_active_rustaceanvim_clients(90, { method = "unrelated" }) == 3,
			"startup filter changed buffer/method-specific queries"
		)
		if config.nested then
			local before = ids()
			config.nested()
			assert(vim.deep_equal(ids(), before), "nested startup did not restore outer project view")
		end
		if config.callback_error then
			error("native callback failure")
		end
		return "native-result", root
	end)
end
package.loaded["rustaceanvim.lsp"] = lsp
package.loaded["rustaceanvim.cargo"] = cargo
package.loaded["rustaceanvim.rust_analyzer"] = analyzer
local status_calls = 0
local status = {
	handler = function()
		status_calls = status_calls + 1
		return "native-status"
	end,
}
package.loaded["rustaceanvim.server_status"] = status
package.loaded["config.rust_clients"] = nil
local function restored()
	assert(cargo.get_config_root_dir == native_resolve, "root resolver was not restored")
	assert(analyzer.get_active_rustaceanvim_clients == native_clients, "global client filter leaked outside startup")
end
local ok, err = pcall(function()
	local boundary = require("config.rust_clients")
	boundary.setup()
	local status_client = {
		id = 1,
		initialized = true,
		is_stopped = function()
			return false
		end,
	}
	assert(not boundary.ready(status_client), "initializing client was marked quiescent")
	assert(
		status.handler(nil, { quiescent = true }, { client_id = 1 }) == "native-status",
		"status handler result changed"
	)
	assert(boundary.ready(status_client) and status_calls == 1, "native status chain did not update readiness")
	status.handler(nil, { quiescent = false }, { client_id = 1 })
	assert(not boundary.ready(status_client) and status_calls == 2, "indexing status retained stale readiness")
	local wrapped = lsp.start
	boundary.setup()
	assert(lsp.start == wrapped, "boundary setup was not idempotent")
	lsp.start(1)
	restored()
	lsp.start(2)
	restored()
	-- Roots can resolve in a different order from buffer entry.
	local result, root = pending[2]()
	assert(result == "native-result" and root == b, "native callback results changed")
	restored()
	pending[1]()
	restored()
	assert(
		vim.deep_equal(observed[1].ids, { 2 }) and vim.deep_equal(observed[2].ids, { 1 }),
		"asynchronous roots shared clients"
	)

	metadata[3].sync = true
	lsp.start(3)
	restored()
	assert(vim.deep_equal(observed[#observed].ids, { 1 }), "canonical root alias lost its own client")
	metadata[4].sync = true
	lsp.start(4)
	restored()
	assert(vim.deep_equal(observed[#observed].ids, { 1 }), "standalone root fallback changed")

	metadata[1].sync, metadata[2].sync = true, true
	metadata[1].nested = function()
		lsp.start(2)
	end
	lsp.start(1)
	restored()
	assert(
		vim.deep_equal(observed[#observed - 1].ids, { 1 }) and vim.deep_equal(observed[#observed].ids, { 2 }),
		"nested client filters compounded or leaked"
	)
	metadata[1].nested = nil

	metadata[2].callback_error = true
	local callback_ok, callback_err = pcall(lsp.start, 2)
	assert(not callback_ok and tostring(callback_err):find("native callback failure", 1, true))
	restored()
	metadata[2].callback_error, metadata[2].sync = nil, false
	metadata[2].callback_error = true
	lsp.start(2)
	restored()
	local async_ok, async_err = pcall(pending[#pending])
	assert(not async_ok and tostring(async_err):find("native callback failure", 1, true))
	restored()
	metadata[2].callback_error = nil
	metadata[1].start_error = true
	local start_ok, start_err = pcall(lsp.start, 1)
	assert(not start_ok and tostring(start_err):find("native start failure", 1, true))
	restored()
	vim.fn.mkdir(a .. "/nested", "p")
	vim.fn.mkdir(fixture .. "/application", "p")
	vim.fn.writefile({ "" }, a .. "/nested/main.rs")
	local sibling = { id = 4, config = { root_dir = fixture .. "/application" } }
	local nested = { id = 5, config = { root_dir = a .. "/nested" } }
	clients[#clients + 1], clients[#clients + 2] = sibling, nested
	assert(
		analyzer.get_client_for_file(fixture .. "/application/main.rs") == sibling,
		"sibling directory prefix selected another client"
	)
	assert(
		analyzer.get_client_for_file(a .. "/nested/main.rs") == nested,
		"nested root did not select most-specific client"
	)
	assert(
		analyzer.get_client_for_file(fixture .. "/alias-a/nested/main.rs") == nested,
		"symlink file lookup lost canonical root"
	)
	assert(analyzer.get_client_for_file(a .. "/nested/main.rs", "specific") == clients[1], "method filter was ignored")
	assert(calls[#calls].filter.method == "specific", "native client provider did not receive method filter")
	assert(analyzer.get_client_for_file(fixture .. "/unknown/main.rs") == nil, "unrelated file acquired a client")
	assert(analyzer.get_client_for_file(a .. "-other/main.rs") == nil, "unowned sibling prefix acquired a client")
	assert(analyzer.get_client_for_file(a) == clients[1], "exact root lookup changed")
	table.remove(clients)
	table.remove(clients)
	assert(
		#clients == 3 and clients[1].config.root_dir == a and clients[2].config.root_dir == b,
		"client registry or roots were mutated"
	)
end)
for _, name in ipairs(names) do
	package.loaded[name] = saved[name]
end
vim.fn.delete(fixture, "rf")
assert(ok, err)
print("RUST_CLIENTS_COMPLETE")
