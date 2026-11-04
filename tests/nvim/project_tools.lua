-- Native source resolution and real editor UI, with in-process LSP fixtures.
-- Opening a report must not format, send formatting requests or mutate source.
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
require("lazy").load({ plugins = { "nvim-lspconfig", "conform.nvim" } })
assert(vim.fn.exists(":ProjectTools") == 2)
local inspect = require("config.project_tools")
local conform = require("conform")
local root = assert(vim.uv.fs_realpath(assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/project-tools-XXXXXX"))))
local buffers, clients, counters = {}, {}, { requests = 0, launches = 0, formats = 0 }
local original_cwd, original_system, original_format = vim.fn.getcwd(), vim.system, conform.format
local original_ft = conform.formatters_by_ft.project_tools_fixture
local original_formatter = conform.formatters.project_tools_fixture
local namespaces = {}
local ok, err = xpcall(function()
	conform.formatters_by_ft.project_tools_fixture = { "project_tools_fixture", lsp_format = "fallback" }
	conform.formatters.project_tools_fixture = {
		command = "/bin/cat",
		stdin = true,
		cwd = function(_, ctx)
			return vim.fs.dirname(ctx.filename)
		end,
	}
	for _, name in ipairs({ "A", "B" }) do
		local directory = root .. "/" .. name
		vim.fn.mkdir(directory, "p")
		local filename = directory .. "/source.txt"
		vim.fn.writefile({ "unsaved sentinel " .. name }, filename)
		vim.cmd("noautocmd edit " .. vim.fn.fnameescape(filename))
		local buf = vim.api.nvim_get_current_buf()
		buffers[#buffers + 1] = buf
		vim.bo[buf].filetype = "project_tools_fixture"
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "draft " .. name })
		local id = vim.lsp.start({
			name = "project-tools-" .. name,
			root_dir = directory,
			cmd = function(dispatchers)
				counters.launches = counters.launches + 1
				local closing, request_id = false, 0
				return {
					request = function(method, _, callback)
						request_id = request_id + 1
						if method == "textDocument/formatting" then
							counters.requests = counters.requests + 1
						end
						vim.schedule(function()
							callback(
								nil,
								method == "initialize" and { capabilities = { documentFormattingProvider = true } }
									or {}
							)
						end)
						return true, request_id
					end,
					notify = function(method)
						if method == "exit" then
							closing = true
							dispatchers.on_exit(0, 0)
						end
						return true
					end,
					is_closing = function()
						return closing
					end,
					terminate = function()
						closing = true
					end,
				}
			end,
		}, { bufnr = buf })
		assert(id)
		clients[#clients + 1] = id
		assert(vim.wait(5000, function()
			return vim.lsp.get_client_by_id(id).initialized
		end, 10))
	end
	vim.cmd.cd(vim.fn.fnameescape(root .. "/B"))
	local a, b = buffers[1], buffers[2]
	local namespace_a = vim.api.nvim_create_namespace("ProjectTools/diagnostics-A")
	local namespace_b = vim.api.nvim_create_namespace("ProjectTools/diagnostics-B")
	namespaces = { namespace_a, namespace_b }
	vim.diagnostic.set(
		namespace_a,
		a,
		{ { lnum = 0, col = 0, message = "first", source = "fixture-a", severity = vim.diagnostic.severity.ERROR } }
	)
	vim.diagnostic.set(
		namespace_b,
		a,
		{ { lnum = 0, col = 0, message = "second", source = "fixture-b", severity = vim.diagnostic.severity.WARN } }
	)
	vim.diagnostic.set(namespace_b, b, {
		{
			lnum = 0,
			col = 0,
			message = "other project",
			source = "fixture-b",
			severity = vim.diagnostic.severity.HINT,
		},
	})
	vim.b[a].autoformat = false
	local source = {
		lines = vim.api.nvim_buf_get_lines(a, 0, -1, false),
		tick = vim.api.nvim_buf_get_changedtick(a),
		cwd = vim.fn.getcwd(),
		path = vim.env.PATH,
		buf = vim.api.nvim_get_current_buf(),
	}
	vim.system = function()
		error("ProjectTools inspection must not execute a process")
	end
	conform.format = function()
		counters.formats = counters.formats + 1
		error("ProjectTools inspection must not format")
	end
	local info = inspect.snapshot(a)
	assert(info.buffer == a and info.file == root .. "/A/source.txt")
	assert(info.autoformat == false and #info.clients == 1)
	assert(info.clients[1].id == clients[1] and info.clients[1].root == root .. "/A")
	assert(info.clients[1].command == "custom transport (not evaluated)")
	assert(#info.diagnostics == 2)
	assert(info.diagnostics[1].counts[1] == 1 and info.diagnostics[2].counts[2] == 1)
	assert(#info.conform.planned == 1 and info.conform.planned[1].command == "/bin/cat")
	assert(info.conform.planned[1].cwd == root .. "/A" and not info.conform.lsp)
	assert(#info.errors == 0, vim.inspect(info.errors))
	assert(info.formatters[1].name == "conform.nvim" and info.formatters[1].active)
	assert(not info.formatters[2].active and info.formatters[2].name == "LSP")
	assert(vim.deep_equal(source.lines, vim.api.nvim_buf_get_lines(a, 0, -1, false)))
	assert(source.tick == vim.api.nvim_buf_get_changedtick(a) and vim.bo[a].modified)
	assert(
		source.cwd == vim.fn.getcwd() and source.path == vim.env.PATH and source.buf == vim.api.nvim_get_current_buf()
	)
	assert(counters.formats == 0 and counters.requests == 0 and counters.launches == 2)
	local editor = vim.api.nvim_get_current_win()
	vim.cmd("ProjectTools")
	local report = vim.api.nvim_get_current_buf()
	assert(report ~= b and vim.bo[report].buftype == "nofile" and not vim.bo[report].modifiable)
	local report_text = table.concat(vim.api.nvim_buf_get_lines(report, 0, -1, false), "\n")
	assert(report_text:find(root .. "/B/source.txt", 1, true))
	assert(not report_text:find(root .. "/A/source.txt", 1, true))
	assert(report_text:find("stored counts, not duplicate detection", 1, true))
	vim.fn.feedkeys("q", "xt")
	assert(not vim.api.nvim_buf_is_valid(report))
	assert(vim.api.nvim_get_current_win() == editor and vim.api.nvim_get_current_buf() == b)
	assert(counters.formats == 0 and counters.requests == 0 and counters.launches == 2)
	-- A faulty inspection provider is visibly unavailable, not silently healthy.
	local old_plan = conform.list_formatters_to_run
	conform.list_formatters_to_run = function()
		error("injected unavailable formatter detail")
	end
	local broken_ok, broken = pcall(inspect.snapshot, b)
	conform.list_formatters_to_run = old_plan
	assert(broken_ok and #broken.errors == 1 and broken.errors[1]:find("injected unavailable", 1, true))
	assert(table.concat(inspect.lines(broken), "\n"):find("Unavailable inspection details", 1, true))
	assert(#broken.clients == 1 and broken.clients[1].id == clients[2])
end, debug.traceback)
vim.system, conform.format = original_system, original_format
conform.formatters_by_ft.project_tools_fixture = original_ft
conform.formatters.project_tools_fixture = original_formatter
for _, ns in ipairs(namespaces) do
	vim.diagnostic.reset(ns)
end
for _, id in ipairs(clients) do
	local client = vim.lsp.get_client_by_id(id)
	if client then
		client:stop(true)
	end
end
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.cmd.cd(vim.fn.fnameescape(original_cwd))
assert(ok, err)
print("PROJECT_TOOLS_COMPLETE")
