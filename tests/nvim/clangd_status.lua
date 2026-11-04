-- Real CMake databases and clangd parsing; all projects/configs are fixtures.
-- Headless execution precedes VeryLazy; load the same public autocmd commands.
require("lazyvim.config").load("autocmds")
local status = require("config.clangd_status")
local shutdown = dofile("tests/nvim/lsp_shutdown.lua")
local root =
	assert(vim.uv.fs_realpath(assert(vim.uv.fs_mkdtemp(assert(vim.uv.os_tmpdir()) .. "/clangd-status-XXXXXX"))))
local cwd = vim.fn.getcwd()
local clients_before, buffers = {}, {}
for _, client in ipairs(vim.lsp.get_clients()) do
	clients_before[client.id] = true
end
local evidence = { observations = {} }
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function expected(value, standard)
	return {
		"#if CONTEXT != " .. value .. " || __cplusplus " .. (standard == 23 and "< 202302L" or "!= 201703L"),
		"#error ContextUnavailable",
		"#endif",
		"int main() { return 0; }",
	}
end
local function fixture(name, value)
	local dir = root .. "/" .. name
	write(dir .. "/.cxx.toml", { "schema = 1" })
	write(
		dir .. "/.clangd",
		{ "CompileFlags:", "  CompilationDatabase: build/dev", "", "Diagnostics:", "  MissingIncludes: Strict" }
	)
	write(dir .. "/CMakeLists.txt", {
		"cmake_minimum_required(VERSION 3.25)",
		"project(flags LANGUAGES CXX)",
		"set(CMAKE_EXPORT_COMPILE_COMMANDS ON)",
		"add_executable(example main.cpp)",
		"set_property(TARGET example PROPERTY CXX_STANDARD ${LANGUAGE_STANDARD})",
		"target_compile_definitions(example PRIVATE CONTEXT=${CONTEXT_VALUE})",
	})
	write(dir .. "/CMakePresets.json", {
		vim.json.encode({
			version = 6,
			configurePresets = {
				{
					name = "dev",
					generator = "Ninja",
					binaryDir = "${sourceDir}/build/dev",
					cacheVariables = { LANGUAGE_STANDARD = "23", CONTEXT_VALUE = tostring(value) },
				},
				{
					name = "alt",
					generator = "Ninja",
					binaryDir = "${sourceDir}/build/alt",
					cacheVariables = { LANGUAGE_STANDARD = "17", CONTEXT_VALUE = "17" },
				},
			},
		}),
	})
	write(dir .. "/main.cpp", expected(value, 23))
	return dir
end
local function configure(dir, preset)
	local result = vim.system({ "cmake", "--preset", preset }, { cwd = dir, text = true }):wait()
	assert(result.code == 0, result.stderr)
	evidence.observations[#evidence.observations + 1] = { configure = preset, project = dir, exit = result.code }
end
local function open(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	buffers[buf] = true
	return buf
end
local function attached(buf, different)
	local client
	assert(
		vim.wait(15000, function()
			local list = vim.lsp.get_clients({ name = "clangd", bufnr = buf })
			client = list[1]
			return #list == 1
				and client.initialized
				and not client:is_stopped()
				and not client._handle_restart
				and (not different or client.id ~= different)
		end, 20),
		"Expected one initialized clangd for " .. vim.api.nvim_buf_get_name(buf)
	)
	return client
end
local function diagnostics(client, buf)
	return vim.diagnostic.get(buf, { namespace = vim.lsp.diagnostic.get_namespace(client.id) })
end
local function parsed(client, buf)
	local reply = client:request_sync(
		"textDocument/semanticTokens/full",
		{ textDocument = { uri = vim.uri_from_bufnr(buf) } },
		15000,
		buf
	)
	assert(reply and not reply.err and reply.result, vim.inspect(reply))
end
local function clean(client, buf)
	parsed(client, buf)
	assert(
		vim.wait(15000, function()
			return #diagnostics(client, buf) == 0
		end, 20),
		"Incorrect project compile flags: " .. vim.inspect(diagnostics(client, buf))
	)
end
local function refresh(buf, previous)
	assert(buf == vim.api.nvim_get_current_buf())
	assert(vim.fn.exists(":ClangdProjectRefresh") == 2, "Missing public current-project refresh command")
	vim.cmd.ClangdProjectRefresh()
	local client = attached(buf, previous.id)
	clean(client, buf)
	return client
end
local ok, err = xpcall(function()
	local a, b = fixture("a", 23), fixture("b", 77)
	vim.cmd.cd(vim.fn.fnameescape(a))
	local abuf = open(a .. "/main.cpp")
	local aclient = attached(abuf)
	assert(vim.wait(15000, function()
		return #diagnostics(aclient, abuf) > 0
	end, 20))
	evidence.initial = {
		id = aclient.id,
		options = vim.deepcopy(aclient.config.init_options),
		diagnostics = diagnostics(aclient, abuf),
		status = status.snapshot(abuf),
	}
	assert(not evidence.initial.options.compilationDatabasePath)
	assert(not evidence.initial.status.clients[1].managed_default_exists)
	configure(a, "dev")
	configure(b, "dev")
	local bbuf = open(b .. "/main.cpp")
	local bclient = attached(bbuf)
	clean(bclient, bbuf)
	assert(bclient.id ~= aclient.id)
	local foreign, why = status.refresh(abuf)
	assert(not foreign and why:find("Select the source file", 1, true))
	assert(attached(bbuf).id == bclient.id and attached(abuf).id == aclient.id)
	vim.api.nvim_set_current_buf(abuf)
	local header = root .. "/external/sdk.hpp"
	write(header, { "struct SharedHeader {};" })
	assert(vim.lsp.util.show_document({
		uri = vim.uri_from_fname(header),
		range = { start = { line = 0, character = 7 }, ["end"] = { line = 0, character = 19 } },
	}, aclient.offset_encoding, { focus = true }))
	local hbuf = vim.api.nvim_get_current_buf()
	buffers[hbuf] = true
	assert(attached(hbuf).id == aclient.id, "Source navigation gave the external header another project")
	evidence.header_before = { id = aclient.id, bufnr = hbuf }
	vim.api.nvim_set_current_buf(abuf)
	local first_id = aclient.id
	aclient = refresh(abuf, aclient)
	assert(attached(hbuf).id == aclient.id, "Native restart lost the project's external header buffer")
	assert(attached(bbuf).id == bclient.id, "Targeted refresh restarted another project")
	local view = status.snapshot(abuf)
	assert(view.clients[1].databases[1].source == "managed startup pin")
	assert(view.clients[1].databases[1].path == a .. "/build/dev/compile_commands.json")
	assert(#view.clients[1].databases[1].records == 1)
	local record = view.clients[1].databases[1].records[1]
	assert(
		record.command and record.command:find("CONTEXT=23", 1, true)
			or record.arguments and vim.tbl_contains(record.arguments, "-DCONTEXT=23")
	)
	evidence.after_first_refresh = { previous = first_id, id = aclient.id, other_id = bclient.id, status = view }
	-- A different native preset does not silently replace the project's clangd
	-- database policy. Report the difference, and respect a deliberate .clangd edit.
	configure(a, "alt")
	assert(status.snapshot(abuf).clients[1].databases[1].path == a .. "/build/dev/compile_commands.json")
	write(a .. "/.clangd", { "CompileFlags:", "  CompilationDatabase: build/alt" })
	vim.api.nvim_buf_set_lines(abuf, 0, -1, false, expected(17, 17))
	vim.cmd.write()
	local old = aclient.id
	aclient:_restart(aclient.exit_timeout)
	aclient = attached(abuf, old)
	parsed(aclient, abuf)
	assert(
		vim.wait(15000, function()
			for _, d in ipairs(diagnostics(aclient, abuf)) do
				if d.message:find("ContextUnavailable", 1, true) then
					return true
				end
			end
			return false
		end, 20),
		"Original native restart unexpectedly discarded the old startup pin"
	)
	evidence.old_restart = {
		id = aclient.id,
		options = vim.deepcopy(aclient.config.init_options),
		diagnostics = diagnostics(aclient, abuf),
	}
	aclient = refresh(abuf, aclient)
	assert(
		not aclient.config.init_options.compilationDatabasePath,
		"Owned old pin survived custom configuration refresh"
	)
	assert(attached(bbuf).id == bclient.id, "Custom-policy refresh restarted another project")
	assert(attached(hbuf).id == aclient.id, "Custom-policy refresh lost the external header")
	view = status.snapshot(abuf)
	assert(#view.clients[1].databases == 0 and view.clients[1].clangd_config == a .. "/.clangd")
	evidence.custom = { id = aclient.id, status = view, diagnostics = diagnostics(aclient, abuf) }
	-- Explicit command-line and initialization databases survive targeted refresh.
	for _, mode in ipairs({ "init", "argv" }) do
		local project = fixture("explicit-" .. mode, 66)
		configure(project, "dev")
		write(project .. "/.clangd", { "Diagnostics:", "  MissingIncludes: None" })
		local buf = vim.api.nvim_create_buf(false, true)
		buffers[buf] = true
		vim.bo[buf].buftype = ""
		vim.api.nvim_buf_set_name(buf, project .. "/main.cpp")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, expected(66, 23))
		vim.bo[buf].modified = false
		local config = vim.deepcopy(vim.lsp.config.clangd)
		config.name = "clangd"
		config.root_dir = project
		config.init_options = vim.deepcopy(config.init_options or {})
		if mode == "init" then
			config.init_options.compilationDatabasePath = project .. "/build/dev"
		else
			config.cmd[#config.cmd + 1] = "--compile-commands-dir=" .. project .. "/build/dev"
		end
		local id = assert(vim.lsp.start(config, {
			bufnr = buf,
			reuse_client = function()
				return false
			end,
		}))
		vim.bo[buf].filetype = "cpp"
		vim.api.nvim_set_current_buf(buf)
		local client = attached(buf)
		assert(client.id == id)
		clean(client, buf)
		local before = vim.deepcopy(client.config)
		client = refresh(buf, client)
		assert(vim.deep_equal(client.config.cmd, before.cmd))
		assert(client.config.init_options.compilationDatabasePath == before.init_options.compilationDatabasePath)
		assert(
			status.snapshot(buf).clients[1].databases[1].source
				== (mode == "init" and "initialization override" or "command-line override")
		)
		assert(attached(bbuf).id == bclient.id)
		evidence.observations[#evidence.observations + 1] =
			{ explicit = mode, old_id = id, new_id = client.id, diagnostics = diagnostics(client, buf) }
	end
end, debug.traceback)
local path = vim.fs.joinpath(vim.fn.stdpath("state"), "clangd-status-evidence.json")
vim.fn.writefile({ vim.json.encode(evidence) }, path)
print("CLANGD_STATUS_EVIDENCE " .. path)
local created = vim.tbl_filter(function(client)
	return not clients_before[client.id]
end, vim.lsp.get_clients())
shutdown(created, "clangd-status", 10000)
vim.cmd.cd(vim.fn.fnameescape(cwd))
for buf in pairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.fn.delete(root, "rf")
assert(ok, err)
print("CLANGD_STATUS_COMPLETE")
