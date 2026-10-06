-- Real clangd evidence for project-external headers. No SDK or user files change.
local context = require("config.clangd_context")
assert(vim.lsp.config.clangd.root_dir == context.root_dir, "clangd root policy is not installed")
assert(vim.lsp.config.clangd.before_init == context.before_init, "clangd database policy is not installed")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local cwd = vim.fn.getcwd()
local shutdown = dofile("tests/nvim/lsp_shutdown.lua")
local original_clients, buffers = {}, {}
for _, client in ipairs(vim.lsp.get_clients()) do
	original_clients[client.id] = true
end
local legacy = { "CompileFlags:", "  CompilationDatabase: build/dev", "", "Diagnostics:", "  MissingIncludes: Strict" }
local stock = {
	"CompileFlags:",
	"  CompilationDatabase: build/dev",
	"",
	"---",
	"If:",
	"  PathMatch: [(src|include|tests)/.*, '[^/]+\\.(c|cc|cpp|cxx|h|hh|hpp|hxx|inc)']",
	"",
	"Diagnostics:",
	"  MissingIncludes: Strict",
}
local ignore = { "  Includes:", "    IgnoreHeader: 'dependency/private/.*'" }
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function fixture(name, std, language, value)
	local project = root .. "/projects/" .. name
	local source = project .. "/src/main." .. (language == "c" and "c" or "cpp")
	write(project .. "/.cxx.toml", { "schema = 1" })
	write(project .. "/.clangd", stock)
	write(source, { "int main(void) { return 0; }" })
	local database = require("config.cpp").compile_database(project)
	write(database, {
		vim.json.encode({
			{
				directory = project,
				file = source,
				arguments = {
					language == "c" and "clang" or "clang++",
					"-std=" .. std,
					"-DPROJECT_CONTEXT=" .. value,
					"-c",
					source,
				},
			},
		}),
	})
	local header = root .. "/sdk/" .. name .. "/external.h"
	local condition = language == "c" and "!defined(__cplusplus) && __STDC_VERSION__ == 201710L"
		or (std == "c++23" and "__cplusplus >= 202302L" or "__cplusplus == 201703L")
	write(header, {
		"#if PROJECT_CONTEXT == " .. value .. " && " .. condition,
		"struct ActiveContext { int member; };",
		"#else",
		"struct WrongContext { int member; };",
		"#endif",
	})
	return project, source, header
end
local function open(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	buffers[buf] = true
	return buf
end
local function clear_origin()
	for _ = 1, 2 do
		local buf = vim.api.nvim_create_buf(false, true)
		buffers[buf] = true
		vim.api.nvim_set_current_buf(buf)
	end
end
local function attached(buf)
	local clients
	assert(
		vim.wait(15000, function()
			clients = vim.lsp.get_clients({ name = "clangd", bufnr = buf })
			return #clients == 1 and clients[1].initialized
		end, 20),
		"clangd did not attach exactly once: " .. vim.api.nvim_buf_get_name(buf)
	)
	return clients[1]
end
local function verify(buf, project)
	local client = attached(buf)
	assert(client.root_dir == project, "header borrowed a different project's client")
	local reply, err = client:request_sync("textDocument/semanticTokens/full", {
		textDocument = vim.lsp.util.make_text_document_params(buf),
	}, 15000, buf)
	assert(reply and not reply.err and reply.result, vim.inspect(reply or err))
	local types = client.server_capabilities.semanticTokensProvider.legend.tokenTypes
	local row, col, active, inactive = 0, 0, false, false
	for i = 1, #reply.result.data, 5 do
		local data = reply.result.data
		if data[i] > 0 then
			col = 0
		end
		row, col = row + data[i], col + data[i + 1]
		local kind = types[data[i + 3] + 1]
		if row == 1 and col == 7 and kind == "class" then
			active = true
		end
		if row == 3 and kind == "comment" then
			inactive = true
		end
	end
	assert(active, "external header lost project language standard or macro: " .. project)
	assert(inactive, "genuinely inactive branch no longer has comment evidence")
	return client
end
local function initialization(project, options, cmd)
	local config = { root_dir = project, init_options = options, cmd = cmd or { "clangd" } }
	local params = { initializationOptions = options or vim.NIL }
	context.before_init(params, config)
	return params.initializationOptions, config.init_options
end

local ok, err = xpcall(function()
	local p23, source, header = fixture("cpp23", "c++23", "cpp", 23)
	local p17, _, header17 = fixture("cpp17", "c++17", "cpp", 17)
	local pc, _, headerc = fixture("c17", "c17", "c", 117)
	for _, layout in ipairs({ legacy, stock }) do
		for _, mode in ipairs({ "Strict", "None" }) do
			for _, extra in ipairs({ {}, ignore }) do
				local lines = vim.deepcopy(layout)
				lines[#lines] = "  MissingIncludes: " .. mode
				write(p23 .. "/.clangd", vim.list_extend(lines, extra))
				assert(initialization(p23).compilationDatabasePath == p23 .. "/build/dev")
			end
		end
	end
	local params, options = initialization(p23, { usePlaceholders = true })
	assert(params.compilationDatabasePath == p23 .. "/build/dev" and options == params)
	assert(params.usePlaceholders, "existing initialization options lost")
	for _, command in ipairs({
		{ "clangd", "--compile-commands-dir=/explicit" },
		{ "clangd", "--compile-commands-dir", "/explicit" },
	}) do
		assert(initialization(p23, nil, command) == vim.NIL, "explicit command database overridden")
	end
	assert(initialization(p23, { compilationDatabasePath = "/explicit" }).compilationDatabasePath == "/explicit")
	for _, custom in ipairs({
		{ "CompileFlags:", "  CompilationDatabase: None" },
		{ "CompileFlags:", "  CompilationDatabase: build/other" },
		{ "If:", "  PathMatch: src/.*", unpack(stock) },
		vim.list_extend(vim.deepcopy(stock), { "---", "CompileFlags:", "  CompilationDatabase: None" }),
		vim.list_extend(
			vim.deepcopy(stock),
			{ "---", "If:", "  PathMatch: vendor/.*", "CompileFlags:", "  CompilationDatabase: build/other" }
		),
		vim.list_extend(
			vim.deepcopy(stock),
			{ "  Includes:", "    IgnoreHeader: 'library/.*'", "CompileFlags:", "  CompilationDatabase: None" }
		),
	}) do
		write(p23 .. "/.clangd", custom)
		assert(initialization(p23) == vim.NIL, "custom project discovery overridden")
	end
	local import_std = vim.deepcopy(stock)
	import_std[#import_std] = "  MissingIncludes: None"
	write(p23 .. "/.clangd", import_std)
	assert(initialization(p23).compilationDatabasePath == p23 .. "/build/dev")
	write(p23 .. "/.clangd", vim.list_extend(vim.deepcopy(stock), ignore))
	write(p17 .. "/.clangd", vim.list_extend(vim.deepcopy(legacy), ignore))
	write(pc .. "/.clangd", stock)
	vim.fn.delete(p23 .. "/.cxx.toml")
	assert(initialization(p23) == vim.NIL, "unmanaged project pinned")
	write(p23 .. "/.cxx.toml", { "schema = 1" })
	assert(vim.uv.fs_rename(p23 .. "/build/dev/compile_commands.json", p23 .. "/saved.json"))
	assert(initialization(p23) == vim.NIL, "missing database pinned")
	assert(vim.uv.fs_rename(p23 .. "/saved.json", p23 .. "/build/dev/compile_commands.json"))

	-- The header is deliberately NOT included: inheritance must not depend on
	-- an includer cache (e.g. SDK aliases or opening a header before its source).
	vim.cmd.cd(vim.fn.fnameescape(p23))
	local source_client = attached(open(source))
	assert(vim.lsp.util.show_document({
		uri = vim.uri_from_fname(header),
		range = {
			start = { line = 1, character = 7 },
			["end"] = { line = 1, character = 20 },
		},
	}, source_client.offset_encoding, { focus = true }))
	local header_buf = vim.api.nvim_get_current_buf()
	buffers[header_buf] = true
	assert(verify(header_buf, p23).id == source_client.id, "header jump started a second clangd")

	-- A header with its own project must never inherit the previous project's
	-- standard. Root markers also work in non-git projects.
	local owned_header = p17 .. "/owned.hpp"
	write(owned_header, vim.fn.readfile(header17))
	assert(verify(open(owned_header), p17).id ~= source_client.id)

	-- Reset the navigation origin; cold-open external headers follow only a
	-- stock managed cwd. C++17 and C17 must not be silently promoted to C++23.
	for _, case in ipairs({ { p17, header17 }, { pc, headerc } }) do
		clear_origin()
		vim.cmd.cd(vim.fn.fnameescape(case[1]))
		verify(open(case[2]), case[1])
	end
	-- Revisiting a shared SDK buffer from another project must not attach a
	-- second client and superimpose contradictory semantic tokens.
	assert(verify(open(header), p23).id == source_client.id)
	vim.cmd.cd(vim.fn.fnameescape(root))
	clear_origin()
	local unrelated = open(root .. "/unmanaged.cpp")
	local selected = false
	context.root_dir(unrelated, function(dir)
		selected = dir
	end)
	assert(selected == nil, "unrelated source borrowed a project root")
end, debug.traceback)

vim.cmd.cd(vim.fn.fnameescape(cwd))
local created = vim.tbl_filter(function(client)
	return not original_clients[client.id]
end, vim.lsp.get_clients())
shutdown(created, "clangd-header-context", 10000)
for buf in pairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.fn.delete(root, "rf")
assert(ok, err)
print(
	"Clangd external header context passed: source jump, C++23/C++17/C17, project isolation, native inactive regions."
)
