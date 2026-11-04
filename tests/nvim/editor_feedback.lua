-- Real editor save/formatter/diagnostic feedback in isolated, dependency-free
-- projects. This observes the installed tools; it does not replace their work.
local root = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/editor-feedback-XXXXXX"))
root = assert(vim.uv.fs_realpath(root))
local original_cwd = vim.fn.getcwd()
local shutdown = dofile("tests/nvim/lsp_shutdown.lua")
local record = dofile("tests/nvim/ci_evidence.lua").open("editor-feedback")
local active_case = { phase = "startup" }
local environment = {
	RUSTUP_AUTO_INSTALL = vim.env.RUSTUP_AUTO_INSTALL,
	CARGO_NET_OFFLINE = vim.env.CARGO_NET_OFFLINE,
	CARGO_TARGET_DIR = vim.env.CARGO_TARGET_DIR,
}
vim.env.RUSTUP_AUTO_INSTALL, vim.env.CARGO_NET_OFFLINE, vim.env.CARGO_TARGET_DIR = "0", "true", nil
local observations, buffers, requests, processes = {}, {}, {}, {}
local function observe(value)
	observations[#observations + 1] = value
	record("observation", value)
end
local system = vim.system
vim.system = function(command, opts, callback)
	processes[#processes + 1] = { command = vim.deepcopy(command), cwd = opts and opts.cwd }
	return system(command, opts, callback)
end
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function wait(label, callback)
	assert(vim.wait(30000, callback, 50), label)
end
local function diagnostics(buf)
	local result = {}
	for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
		result[#result + 1] = {
			lnum = diagnostic.lnum,
			col = diagnostic.col,
			end_col = diagnostic.end_col,
			source = diagnostic.source,
			code = diagnostic.code,
			message = diagnostic.message,
			severity = diagnostic.severity,
			namespace = diagnostic.namespace,
		}
	end
	return result
end
local function has_missing(buf)
	for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
		if diagnostic.message:find("missing_value", 1, true) then
			return diagnostic
		end
	end
end
local traced = {}
local function clients(buf, names)
	local found = {}
	wait("Language servers did not attach: " .. vim.inspect(names), function()
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
			if client.initialized then
				found[client.name] = client
			end
		end
		for _, name in ipairs(names) do
			if not found[name] then
				return false
			end
		end
		return true
	end)
	for _, client in pairs(found) do
		if not traced[client.id] then
			local request = client.request
			client.request = function(self, method, params, handler, bufnr)
				if method == "textDocument/formatting" then
					requests[#requests + 1] = {
						client = client.name,
						id = client.id,
						command = client.config.cmd,
						root = client.root_dir,
						uri = params.textDocument.uri,
					}
				end
				return request(self, method, params, handler, bufnr)
			end
			traced[client.id] = { client = client, request = request }
		end
	end
	return found
end
local function edit(path, names)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	buffers[#buffers + 1] = buf
	clients(buf, names)
	return buf
end
local function save(buf, expected, label)
	local request_start, process_start = #requests, #processes
	local start = vim.uv.hrtime()
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("silent write")
	end)
	local elapsed = (vim.uv.hrtime() - start) / 1e6
	local actual = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	observe({
		case = label,
		file = vim.api.nvim_buf_get_name(buf),
		cwd = vim.fn.getcwd(),
		elapsed_ms = elapsed,
		output = actual,
		formatters = require("conform").list_formatters(buf),
		save_chain = vim.tbl_map(function(item)
			return { name = item.name, active = item.active, sources = item.resolved }
		end, LazyVim.format.resolve(buf)),
		lsp_requests = vim.list_slice(requests, request_start + 1),
		processes = vim.list_slice(processes, process_start + 1),
	})
	local activity = observations[#observations]
	local ft = vim.bo[buf].filetype
	if ft == "c" or ft == "cpp" then
		local formatter_calls = vim.tbl_filter(function(call)
			return vim.fs.basename(call.command[1]) == "clang-format"
		end, activity.processes)
		assert(#formatter_calls == 1 and #activity.lsp_requests == 0, label .. ": wrong actual formatter owner")
		assert(vim.fn.executable(formatter_calls[1].command[1]) == 1, label .. ": formatter is not executable")
	else
		local expected_client = ({ python = "ruff", rust = "rust-analyzer", zig = "zls" })[ft]
		assert(
			#activity.lsp_requests == 1
				and activity.lsp_requests[1].client == expected_client
				and activity.lsp_requests[1].uri == vim.uri_from_bufnr(buf),
			label .. ": wrong actual LSP formatter"
		)
	end
	assert(vim.deep_equal(actual, expected), label .. ": unexpected format " .. vim.inspect(actual))
	assert(vim.deep_equal(vim.fn.readfile(vim.api.nvim_buf_get_name(buf)), expected), label .. ": disk mismatch")
	assert(not vim.bo[buf].modified, label .. ": save left modified text")
end
local diagnostic_sources = {
	c = { clang = "undeclared_var_use" },
	cpp = { clang = "undeclared_var_use" },
	python = { Ruff = "F821", ty = "unresolved-reference" },
	rust = { rustc = "E0425" },
	zig = { zls = false },
}
local function tool_status(buf, language, project, names)
	local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local tick, modified = vim.api.nvim_buf_get_changedtick(buf), vim.bo[buf].modified
	local status = require("config.project_tools").snapshot(buf)
	assert(
		tick == vim.api.nvim_buf_get_changedtick(buf)
			and modified == vim.bo[buf].modified
			and vim.deep_equal(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false)),
		"ProjectTools changed source"
	)
	local expected = (language == "c" or language == "cpp") and "conform.nvim" or "LSP"
	local active = vim.tbl_filter(function(item)
		return item.active
	end, status.formatters)
	assert(#active == 1 and active[1].name == expected, language .. ": wrong ProjectTools active formatter")
	local attached = vim.lsp.get_clients({ bufnr = buf })
	assert(#status.clients == #attached, language .. ": ProjectTools client scope differs")
	for _, name in ipairs(names) do
		local matched = vim.tbl_filter(function(client)
			return client.name == name
		end, status.clients)
		assert(
			#matched == 1 and vim.uv.fs_realpath(matched[1].root) == project,
			language .. ": ProjectTools wrong client root"
		)
	end
	observe({ case = language .. " tool status", file = vim.api.nvim_buf_get_name(buf), status = status })
end
local function case(language, make, names)
	local specs = {}
	for index, variant in ipairs({ "a", "b" }) do
		local project = root .. "/" .. language .. "-" .. variant
		write(project .. "/.git", { "gitdir: unused-fixture" })
		local path, raw, formatted = make(project, index)
		write(path, raw)
		specs[index] = { project = project, path = path, raw = raw, formatted = formatted }
	end
	vim.cmd.cd(vim.fn.fnameescape(specs[2].project))
	for visit, index in ipairs({ 1, 2, 1 }) do
		local spec = specs[index]
		active_case = { language = language, index = index, visit = visit, file = spec.path, phase = "attach" }
		local buf = spec.buf or edit(spec.path, names)
		spec.buf = buf
		active_case.buf = buf
		-- Revisit A in the actual editor window. A temporary buf_call(write)
		-- restores B afterwards, where native visible-only pull diagnostics
		-- correctly skip hidden A. Keep cwd at B to test project isolation.
		vim.api.nvim_set_current_buf(buf)
		assert(vim.api.nvim_get_current_buf() == buf, "Fixture did not switch to the target buffer")
		assert(vim.fn.getcwd() == specs[2].project, "Fixture lost the other project's cwd")
		record(
			"visit",
			vim.tbl_extend("force", active_case, { current = vim.api.nvim_get_current_buf(), cwd = vim.fn.getcwd() })
		)
		wait(language .. " native formatter did not become available", function()
			for _, formatter in ipairs(LazyVim.format.resolve(buf)) do
				if formatter.active then
					return true
				end
			end
			return false
		end)
		assert(LazyVim.format.enabled(buf), "Fixture autoformat disabled")
		local native = clients(buf, names)
		for _, name in ipairs(names) do
			assert(vim.uv.fs_realpath(native[name].root_dir) == spec.project, language .. " wrong project client")
		end
		tool_status(buf, language, spec.project, names)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, spec.raw)
		active_case.phase = "save"
		save(buf, spec.formatted, language .. index .. " save")
		assert(vim.api.nvim_get_current_buf() == buf, "Save left the target buffer hidden")
		assert(vim.fn.getcwd() == specs[2].project, "Save changed the other project's cwd")
		local diagnostic_started = vim.uv.hrtime()
		active_case.phase = "diagnostic"
		wait(language .. " missing native diagnostic", function()
			local expected_col = assert(spec.formatted[2]:find("missing_value", 1, true)) - 1
			for source, code in pairs(diagnostic_sources[language]) do
				local found = false
				for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
					if
						diagnostic.source == source
						and (code == false or diagnostic.code == code)
						and diagnostic.message:find("missing_value", 1, true)
						and diagnostic.lnum == 1
						and diagnostic.col == expected_col
					then
						found = true
					end
				end
				if not found then
					return false
				end
			end
			return true
		end)
		local diagnostic = assert(has_missing(buf))
		assert(diagnostic.lnum == 1, language .. ": wrong diagnostic line: " .. vim.inspect(diagnostic))
		observe({
			case = language .. " diagnostic",
			file = spec.path,
			diagnostics = diagnostics(buf),
			wait_after_save_ms = (vim.uv.hrtime() - diagnostic_started) / 1e6,
		})
		active_case.phase = "idempotent save"
		save(buf, spec.formatted, language .. index .. " idempotent")
		local repaired = vim.tbl_map(function(line)
			return (line:gsub("missing_value", "1"))
		end, spec.formatted)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, repaired)
		active_case.phase = "repair save"
		save(buf, repaired, language .. index .. " repair")
		local repair_started = vim.uv.hrtime()
		active_case.phase = "diagnostic cleared"
		wait(language .. " stale native diagnostic", function()
			return not has_missing(buf)
		end)
		observe({
			case = language .. " cleared",
			file = spec.path,
			diagnostics = diagnostics(buf),
			wait_after_save_ms = (vim.uv.hrtime() - repair_started) / 1e6,
		})
		assert(
			#vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR }) == 0,
			language .. ": remaining error"
		)
	end
	print("EDITOR_FEEDBACK_SAVE_COMPLETE " .. language)
	active_case.phase = "retirement"
	local stopped = {}
	for _, spec in ipairs(specs) do
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = spec.buf })) do
			stopped[client.id] = client
		end
	end
	shutdown(vim.tbl_values(stopped), language .. " editor feedback", 5000)
	print("EDITOR_FEEDBACK_LANGUAGE_COMPLETE " .. language)
end
local ok, failure = xpcall(function()
	-- This contract covers real saving, formatting and AST diagnostics. Keep
	-- background build workers outside that scope, as color_contract does.
	-- The unmodified production BSP mode was separately observed to finish
	-- these assertions but fail graceful retirement on both base and candidate;
	-- this fixture setting does not change production or claim to fix that issue.
	vim.lsp.config("zls", { settings = { zls = { enable_build_on_save = false } } })
	-- Headless command-line contracts run before the normal UI startup event.
	-- Exercise the real registered startup callbacks, not a replacement formatter.
	vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
	require("lazy").load({ plugins = { "conform.nvim", "nvim-lspconfig" } })
	wait("Native format-on-save hook did not initialize", function()
		return vim.fn.exists("#LazyFormat#BufWritePre") == 1
	end)
	for _, language in ipairs({ "c", "cpp" }) do
		case(language, function(project, index)
			local width = index == 1 and 2 or 6
			write(
				project .. "/.clang-format",
				{ "BasedOnStyle: LLVM", "IndentWidth: " .. width, "AllowShortFunctionsOnASingleLine: None" }
			)
			write(project .. "/.clangd", { "CompileFlags:", "  Add: [-Wall]" })
			local path = project .. "/source." .. language
			local compiler = vim.fn.exepath(language == "c" and "clang" or "clang++")
			write(project .. "/compile_commands.json", {
				vim.json.encode({ { directory = project, file = path, arguments = { compiler, "-c", path } } }),
			})
			local signature = language == "c" and "int answer(void)" or "int answer()"
			return path,
				{ signature .. "{", "return missing_value;", "}" },
				{ signature .. " {", string.rep(" ", width) .. "return missing_value;", "}" }
		end, { "clangd" })
	end
	case("python", function(project, index)
		local quote = index == 1 and "'" or '"'
		write(
			project .. "/pyproject.toml",
			{ "[tool.ruff.format]", 'quote-style = "' .. (index == 1 and "single" or "double") .. '"' }
		)
		return project .. "/source.py",
			{ 'label="hello"', "value=missing_value" },
			{ "label = " .. quote .. "hello" .. quote, "value = missing_value" }
	end, { "ty", "ruff" })
	case("rust", function(project, index)
		local width = index == 1 and 2 or 6
		write(
			project .. "/Cargo.toml",
			{ "[package]", 'name="editor_' .. index .. '"', 'version="0.0.0"', 'edition="2024"' }
		)
		write(project .. "/rustfmt.toml", { "tab_spaces = " .. width })
		return project .. "/src/lib.rs",
			{ "pub fn answer()->i32{", "missing_value", "}" },
			{ "pub fn answer() -> i32 {", string.rep(" ", width) .. "missing_value", "}" }
	end, { "rust-analyzer" })
	case("zig", function(project)
		write(project .. "/zls.json", { "{}" })
		return project .. "/source.zig",
			{ "pub fn answer() i32{", "return missing_value;", "}" },
			{ "pub fn answer() i32 {", "    return missing_value;", "}" }
	end, { "zls" })
end, debug.traceback)
if not ok then
	local snapshot = {
		case = active_case,
		current = vim.api.nvim_get_current_buf(),
		cwd = vim.fn.getcwd(),
		windows = {},
		buffers = {},
	}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		snapshot.windows[#snapshot.windows + 1] = { win = win, buf = vim.api.nvim_win_get_buf(win) }
	end
	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			local item = {
				buf = buf,
				file = vim.api.nvim_buf_get_name(buf),
				tick = vim.api.nvim_buf_get_changedtick(buf),
				diagnostics = diagnostics(buf),
				clients = {},
			}
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
				local pending = {}
				for id, request in pairs(client.requests) do
					pending[#pending + 1] =
						{ id = id, method = request.method, type = request.type, buf = request.bufnr }
				end
				item.clients[#item.clients + 1] = {
					id = client.id,
					name = client.name,
					root = client.root_dir,
					initialized = client.initialized,
					requests = pending,
				}
			end
			snapshot.buffers[#snapshot.buffers + 1] = item
		end
	end
	record("failure", snapshot)
	print("EDITOR_FEEDBACK_FAILURE " .. vim.json.encode(snapshot))
end
vim.system = system
for _, traced_client in pairs(traced) do
	traced_client.client.request = traced_client.request
end
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.fn.chdir(original_cwd)
for key, value in pairs(environment) do
	vim.env[key] = value
end
local evidence = vim.fn.stdpath("state") .. "/editor-feedback.json"
write(evidence, { vim.json.encode(observations) })
print("EDITOR_FEEDBACK_EVIDENCE " .. evidence)
assert(ok, failure)
print("EDITOR_FEEDBACK_COMPLETE")
