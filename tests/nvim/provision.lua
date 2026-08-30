local function provision()
	require("lazy").load({ plugins = { "mason.nvim" } })

	local policy = require("config.mason")
	local tools = LazyVim.opts("mason.nvim").ensure_installed or {}
	local unique = policy.unique(tools)
	assert(#unique == #tools, "Final Mason ensure_installed list contains duplicates")

	local installed = policy.wait_for_installed(unique, vim.env.DOTFILES_MASON_TIMEOUT_MS)
	local names = vim.tbl_map(policy.tool_name, unique)
	table.sort(names)
	print(("Mason missing-tool provisioning %d/%d"):format(installed, #unique))
	print("Mason required tools: " .. table.concat(names, ","))
end

local ok, error_message = xpcall(provision, debug.traceback)
if not ok then
	vim.api.nvim_err_writeln(error_message)
	vim.cmd("cquit 1")
end
