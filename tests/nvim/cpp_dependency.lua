-- Real buffers/writes; no LSP or formatter is needed to enforce ownership.
local policy = require("config.cpp_dependency")
local clangd_enabled
if LazyVim then
	-- Headless smoke starts before VeryLazy would normally load user autocmds.
	require("lazyvim.config").load("autocmds")
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	clangd_enabled = vim.lsp.is_enabled("clangd")
	-- This buffer/write test does not need a server. Avoid scheduling attaches
	-- for temporary buffers that are deleted before the event loop resumes.
	vim.lsp.enable("clangd", false)
end
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local saved_buf, notify = vim.api.nvim_get_current_buf(), vim.notify
local buffers = {}
local function open(relative)
	local path = vim.fs.joinpath(root, relative)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile({ "int  value=1;" }, path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	buffers[#buffers + 1] = buf
	assert(vim.bo[buf].filetype == "cpp")
	return buf, path
end

local ok, err = xpcall(function()
	for _, path in ipairs({
		"/opt/homebrew/include/x.hpp",
		"/usr/local/Cellar/lib/1/include/x.hpp",
		"/home/linuxbrew/.linuxbrew/include/x.hpp",
		"/usr/include/c++/v1/x.hpp",
		"/Applications/Xcode.app/Contents/Developer/SDKs/MacOSX27.sdk/usr/include/c++/v1/x.hpp",
	}) do
		assert(policy.is_dependency(path), path)
	end
	for _, path in ipairs({
		"",
		root .. "/vendor/x.hpp",
		root .. "/src/_deps/x.hpp",
		root .. "/vcpkg_installed_copy/x.hpp",
	}) do
		assert(not policy.is_dependency(path), path)
	end
	for _, relative in ipairs({
		"build/dev/vcpkg_installed/arm64-osx/include/x.cpp",
		"build/san/_deps/lib-src/x.cpp",
		"build/_deps/lib-src/x.cpp",
	}) do
		local buf, path = open(relative)
		assert(vim.b[buf].cpp_dependency and vim.b[buf].autoformat == false, "CPP_DEPENDENCY_PROTECTION_MISSING")
		if LazyVim then
			assert(not LazyVim.format.enabled(buf), "Dependency save-time formatting is enabled")
		end
		assert(vim.bo[buf].readonly and not vim.bo[buf].modifiable)
		assert(
			not pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { "corruption" }),
			"LSP/edit API bypassed protection"
		)
		-- With 'confirm' enabled, refusing a readonly write can return normally.
		-- In both modes, the immutable buffer and original bytes must survive.
		pcall(vim.cmd.write)
		local requested = false
		local get_clients = vim.lsp.get_clients
		vim.lsp.get_clients = function()
			requested = true
			return {}
		end
		vim.notify = function() end
		require("config.clangd_includes").choose()
		vim.lsp.get_clients, vim.notify = get_clients, notify
		assert(not requested, "Include action queried a protected dependency")
		assert(vim.deep_equal(vim.fn.readfile(path), { "int  value=1;" }))
		-- Explicit unlock affects only this buffer; it does not enable autoformat.
		vim.notify = function() end
		vim.cmd.CppDependencyEdit()
		vim.notify = notify
		assert(vim.bo[buf].modifiable and not vim.bo[buf].readonly)
		assert(vim.b[buf].autoformat == false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int value = 2;" })
		vim.cmd.write()
		assert(vim.deep_equal(vim.fn.readfile(path), { "int value = 2;" }))
		vim.cmd.edit()
		assert(vim.bo[buf].readonly and not vim.bo[buf].modifiable, "Reopen failed to restore protection")
	end
	local own = open("src/main.cpp")
	assert(vim.bo[own].modifiable and not vim.bo[own].readonly and vim.b[own].autoformat ~= false)
	vim.api.nvim_buf_set_lines(own, 0, -1, false, { "int value = 3;" })
	vim.cmd.write()
	local link = root .. "/alias.cpp"
	assert(vim.uv.fs_symlink(root .. "/build/_deps/lib-src/x.cpp", link))
	vim.cmd.edit(vim.fn.fnameescape(link))
	buffers[#buffers + 1] = vim.api.nvim_get_current_buf()
	assert(vim.bo.readonly and not vim.bo.modifiable, "Symlink alias bypassed protection")
end, debug.traceback)

vim.notify = notify
vim.api.nvim_set_current_buf(saved_buf)
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.fn.delete(root, "rf")
if clangd_enabled then
	vim.lsp.enable("clangd")
end
assert(ok, err)
print("C++ dependency protection passed: readonly edits/writes, explicit unlock, own source, symlink")
