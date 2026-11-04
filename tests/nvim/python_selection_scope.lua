-- Reproduce the observed generic-LSP root collision through real cache operations.
local context = require("config.python_context")
local fixture = assert(vim.env.DOTFILES_PYTHON_FIXTURES)
fixture = assert(vim.uv.fs_realpath(fixture))
local old = fixture .. "/project-a/.venv/bin/python"
local external = fixture .. "/manual/env/bin/python"
local a, b, shared = fixture .. "/scope-a", fixture .. "/scope-b", fixture .. "/shared-copilot-root"
for _, root in ipairs({ a, b, shared }) do
	vim.fn.mkdir(root .. "/.git", "p")
end
assert(vim.uv.fs_symlink(fixture .. "/project-b/custom-env", b .. "/.venv"))
vim.fn.writefile({ "value = 1" }, a .. "/probe.py")
vim.fn.writefile({ "value = 2" }, b .. "/probe.py")
vim.fn.writefile({ "owner" }, shared .. "/owner.txt")
local function buffer(path, filetype)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, path)
	vim.bo[buf].filetype = filetype
	return buf
end
local a_buf, b_buf, owner =
	buffer(a .. "/probe.py", "python"), buffer(b .. "/probe.py", "python"), buffer(shared .. "/owner.txt", "text")
require("lazy").load({ plugins = { "venv-selector.nvim" } })
local selector = require("venv-selector")
local cache = require("venv-selector.cached_venv")
local roots = require("venv-selector.project_root")
local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function(opts)
	if opts and not opts.name and (opts.bufnr == a_buf or opts.bufnr == b_buf or opts.bufnr == owner) then
		-- Metadata matches the real post-apply trace: only Copilot with a shared cwd.
		return { { name = "copilot", id = -1, config = { root_dir = shared } } }
	end
	return get_clients(opts)
end
local ok, err = pcall(function()
	vim.api.nvim_set_current_buf(b_buf)
	context.activate(b_buf)
	local own = b .. "/.venv/bin/python"
	assert(selector.python() == own, "fresh B did not activate its own environment")
	-- Seed an old shared key through the real cache API without changing user files.
	cache.save(old, "venv", owner)
	cache.ensure_cached_venv_activated(b_buf)
	assert(
		selector.python() == own and context.require_context(b).python == own,
		"unrelated shared LSP cache replaced fresh B's project environment"
	)
	assert(roots.key_for_buf(a_buf) == a and roots.key_for_buf(b_buf) == b, "Python cache roots are not target-scoped")
	assert(roots.key_for_buf(owner) == shared, "non-Python root delegation changed")
	local deleted = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_delete(deleted, { force = true })
	assert(roots.key_for_buf(deleted) == nil, "invalid buffer root delegation changed")

	vim.api.nvim_set_current_buf(a_buf)
	selector.activate_from_path(external, "venv")
	local cache_file = vim.fn.expand(require("venv-selector.config").user_settings.cache.file)
	local saved = vim.json.decode(table.concat(vim.fn.readfile(cache_file), "\n"))
	assert(
		saved[a].value == external and saved[shared].value == old and saved[b] == nil,
		"manual A selection changed another project's cache key"
	)

	-- A correctly scoped persisted external environment must still bootstrap B.
	cache.save(external, "venv", b_buf)
	local callbacks, schedule = {}, vim.schedule
	vim.schedule = function(callback)
		callbacks[#callbacks + 1] = callback
	end
	local retrieved, retrieve_err = pcall(cache.retrieve, b_buf)
	vim.schedule = schedule
	assert(retrieved, retrieve_err)
	assert(#callbacks == 1, "scoped B cache did not produce a real restore callback")
	callbacks[1]()
	assert(
		context.require_context(b).python == external and selector.python() == external,
		"valid scoped external B cache restore was rejected"
	)
end)
vim.lsp.get_clients = get_clients
assert(ok, err)
print("PYTHON_SELECTION_SCOPE_COMPLETE")
