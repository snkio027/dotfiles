-- Keep catalog matching/validation in the real Taplo server. Only the test
-- schema is local, so completion/diagnostic checks do not need the network.
require("lazy").load({ plugins = { "nvim-lspconfig" } })
local configured = LazyVim.opts("nvim-lspconfig").servers.taplo
local hook = assert(configured.before_init, "TAPLO_CATALOG_HOOK_MISSING")
local store = require("schemastore").json
local original_schemas = store.schemas
local entries = store.schemas()
local snapshot = vim.deepcopy(entries)
local config = { settings = { evenBetterToml = { formatter = { indentString = "    " } } } }
hook({}, config)
local uri = config.settings.evenBetterToml.schema.catalogs[1]
local path = vim.uri_to_fname(uri)
local catalog = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(catalog["$schema"] == "https://json.schemastore.org/schema-catalog.json", "TAPLO_CATALOG_IDENTIFIER")
assert(vim.deep_equal(catalog.schemas, snapshot), "TAPLO_CATALOG_ENTRIES_CHANGED")
assert(config.settings.evenBetterToml.formatter.indentString == "    ")
local second = {}
hook({}, second)
assert(second.settings.evenBetterToml.schema.catalogs[1] == uri, "TAPLO_CATALOG_NOT_REUSED")
for _, schema in ipairs({
	{ catalogs = {} },
	{ catalogs = { "file:///custom-catalog.json" } },
	{ enabled = false },
}) do
	local custom = { settings = { evenBetterToml = { schema = schema } } }
	local before = vim.deepcopy(custom)
	hook({}, custom)
	assert(vim.deep_equal(custom, before), "TAPLO_EXPLICIT_SCHEMA_CONFIG_CHANGED")
end
local associations = { [".*custom.toml$"] = "file:///custom-schema.json" }
local custom = { settings = { evenBetterToml = { schema = { associations = associations } } } }
hook({}, custom)
assert(vim.deep_equal(custom.settings.evenBetterToml.schema.associations, associations))

local api = vim.api
local root, buffers, clients = vim.fn.tempname(), {}, {}
vim.fn.mkdir(root, "p")
local function json(name, value)
	local file = root .. "/" .. name
	vim.fn.writefile({ vim.json.encode(value) }, file)
	return vim.uri_from_fname(file)
end
local integer_schema = json("integer.json", {
	type = "object",
	properties = { answer = { type = "integer", description = "The answer." } },
	additionalProperties = false,
})
local string_schema = json("string.json", {
	type = "object",
	properties = { answer = { type = "string" } },
	additionalProperties = false,
})
local last, updates = {}, {}
local function request(client, method, params, buf)
	local response = assert(client:request_sync(method, params, 5000, buf), "TAPLO_REQUEST_TIMEOUT: " .. method)
	assert(not response.err, vim.inspect(response.err))
	return response.result
end
local function start(name, settings)
	local buf = api.nvim_create_buf(false, false)
	buffers[#buffers + 1] = buf
	api.nvim_buf_set_name(buf, root .. "/" .. name)
	api.nvim_buf_set_lines(buf, 0, -1, false, { 'answer = "wrong"' })
	local doc = vim.uri_from_bufnr(buf)
	local id = vim.lsp.start({
		name = "taplo-catalog-contract",
		cmd = { "taplo", "lsp", "stdio" },
		-- No folders avoids Taplo's initial default catalog fetch before it
		-- requests workspace/configuration. Project rules use an explicit file.
		before_init = hook,
		settings = settings
				and vim.tbl_deep_extend("force", vim.deepcopy(configured.settings), { evenBetterToml = settings })
			or vim.deepcopy(configured.settings),
		get_language_id = function()
			return "toml"
		end,
		handlers = {
			["textDocument/publishDiagnostics"] = function(_, result)
				last[result.uri] = result.diagnostics
				updates[result.uri] = (updates[result.uri] or 0) + 1
			end,
		},
	}, {
		bufnr = buf,
		reuse_client = function()
			return false
		end,
	})
	local client = assert(vim.lsp.get_client_by_id(id), "TAPLO_CLIENT_MISSING")
	clients[#clients + 1] = client
	assert(
		vim.wait(10000, function()
			return client.initialized
		end),
		"TAPLO_INITIALIZE_TIMEOUT"
	)
	local loaded
	assert(
		vim.wait(10000, function()
			loaded = request(client, "taplo/listSchemas", { documentUri = doc }, buf).schemas
			return #loaded >= #entries
		end, 50),
		"TAPLO_CATALOG_NOT_LOADED"
	)
	return client, buf, doc
end
local function edit(buf, lines, predicate)
	local doc = vim.uri_from_bufnr(buf)
	local previous = updates[doc] or 0
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	assert(
		vim.wait(5000, function()
			return (updates[doc] or 0) > previous and predicate(last[doc])
		end, 20),
		"TAPLO_DIAGNOSTICS_MISMATCH: " .. vim.inspect(last[doc])
	)
end
local ok, err = xpcall(function()
	-- Add one synthetic entry to the actual installed catalog without
	-- replacing its production entries or the native catalog parser.
	store.schemas = function()
		local all = vim.deepcopy(entries)
		all[#all + 1] = { name = "Contract", fileMatch = { "catalog-probe.toml" }, url = integer_schema }
		return all
	end
	vim.fn.delete(path) -- missing temporary export is safely regenerated
	local client, buf, doc = start("catalog-probe.toml")
	edit(buf, { 'answer = "not an integer"' }, function(diags)
		for _, diagnostic in ipairs(diags) do
			if diagnostic.message:lower():find("integer", 1, true) then
				return true
			end
		end
		return false
	end)
	edit(buf, { "answer = 42" }, function(diags)
		return #diags == 0
	end)
	edit(buf, { "ans" }, function(diags)
		return #diags > 0
	end) -- syntax errors still propagate
	local completion = request(client, "textDocument/completion", {
		textDocument = { uri = doc },
		position = { line = 0, character = 3 },
	}, buf)
	local found = false
	for _, item in ipairs(completion.items or completion) do
		found = found or item.label == "answer"
	end
	assert(found, "TAPLO_SCHEMA_COMPLETION_MISSING")
	edit(buf, { "#:schema " .. string_schema, 'answer = "valid override"' }, function(diags)
		return #diags == 0
	end)
	edit(buf, { "#:schema " .. string_schema, "answer = 42" }, function(diags)
		return #diags > 0
	end)

	local project_config = root .. "/.taplo.toml"
	vim.fn.writefile(
		{ "[[rule]]", 'include = ["catalog-probe.toml"]', "[rule.schema]", 'path = "' .. string_schema .. '"' },
		project_config
	)
	local project_client, project_buf =
		start("project/catalog-probe.toml", { taplo = { configFile = { path = project_config } } })
	edit(project_buf, { 'answer = "project rule wins"' }, function(diags)
		return #diags == 0
	end)
	edit(project_buf, { "answer = 7" }, function(diags)
		return #diags > 0
	end)
	assert(project_client.initialized)
end, debug.traceback)
store.schemas = original_schemas
-- Remove the synthetic export; the next real client regenerates unmodified entries.
local exported = {}
hook({}, exported)
vim.fn.delete(vim.uri_to_fname(exported.settings.evenBetterToml.schema.catalogs[1]))
for _, client in ipairs(clients) do
	client:stop()
end
local stopped = vim.wait(5000, function()
	for _, client in ipairs(clients) do
		if not client:is_stopped() then
			return false
		end
	end
	return true
end)
for _, client in ipairs(clients) do
	if not client:is_stopped() then
		client:stop(true)
	end
end
for _, buf in ipairs(buffers) do
	if api.nvim_buf_is_valid(buf) then
		api.nvim_buf_delete(buf, { force = true })
	end
end
vim.fn.delete(root, "rf")
assert(vim.deep_equal(entries, snapshot), "TAPLO_SCHEMASTORE_MUTATED")
assert(ok, err)
assert(stopped, "TAPLO_STOP_TIMEOUT")
print("Taplo schema contract passed: catalog, native completion/diagnostics, directive and project rule priority")
