local directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local evidence = dofile(directory .. "/ci_evidence.lua")
local record = evidence.open("mason")
local registry, names

local function provision()
	require("lazy").load({ plugins = { "mason.nvim", "nvim-treesitter" } })
	registry = require("mason-registry")
	evidence.watch_mason(registry, record)
	local registry_ready
	require("mason-registry").refresh(function(success)
		registry_ready = success
		record("registry-refresh", { success = success })
	end)
	assert(vim.wait(tonumber(vim.env.DOTFILES_MASON_TIMEOUT_MS) or 900000, function()
		return registry_ready ~= nil
	end, 100) and registry_ready, "Mason registry provisioning failed or timed out")
	require("lazy").load({ plugins = { "nvim-lspconfig" } })

	local policy = require("config.mason")
	local tools = LazyVim.opts("mason.nvim").ensure_installed or {}
	local unique = policy.unique(tools)
	assert(#unique == #tools, "Final Mason ensure_installed list contains duplicates")

	-- LazyVim has two missing-tool owners. mason-lspconfig deliberately skips
	-- its ensure_installed pass in headless mode, so explicitly run that pass
	-- here and wait for the effective LSP list as well as mason.nvim's tools.
	-- Read the compiled settings, preserving disabled/external server policy.
	unique = policy.required_tools()
	assert(not vim.tbl_contains(unique, "clangd"), "Mason must not provision Homebrew clangd")
	assert(not vim.tbl_contains(unique, "rust-analyzer"), "Mason must not provision Homebrew rust-analyzer")
	require("mason-lspconfig.features.ensure_installed")()

	names = vim.tbl_map(policy.tool_name, unique)
	record("before-wait", evidence.mason_snapshot(registry, names))
	local installed = policy.wait_for_installed(unique, vim.env.DOTFILES_MASON_TIMEOUT_MS)
	record("installed", evidence.mason_snapshot(registry, names))
	table.sort(names)
	print(("Mason missing-tool provisioning %d/%d"):format(installed, #unique))
	print("Mason required tools: " .. table.concat(names, ","))

	local parser_languages = { "c", "cpp", "python", "rust", "zig" }
	local parser_timeout = tonumber(vim.env.DOTFILES_TREESITTER_TIMEOUT_MS) or 300000
	local treesitter = require("nvim-treesitter")
	local parser_task = treesitter.install(parser_languages, {
		max_jobs = #parser_languages,
		summary = true,
	})
	local wait_ok, install_ok = parser_task:pwait(parser_timeout)
	assert(wait_ok, ("Tree-sitter evidence parser provisioning did not complete: %s"):format(tostring(install_ok)))
	assert(install_ok == true, "Tree-sitter evidence parser provisioning failed")

	local installed_parsers = treesitter.get_installed("parsers")
	for _, language in ipairs(parser_languages) do
		assert(vim.list_contains(installed_parsers, language), ("Tree-sitter parser is missing: %s"):format(language))
	end
	print(
		("Tree-sitter evidence parser provisioning %d/%d: %s"):format(
			#parser_languages,
			#parser_languages,
			table.concat(parser_languages, ",")
		)
	)
end

local ok, error_message = xpcall(provision, debug.traceback)
if not ok then
	record("failed", { error = error_message })
	if registry and names then
		record("final-state", evidence.mason_snapshot(registry, names))
	end
	vim.api.nvim_err_writeln(error_message)
	vim.cmd("cquit 1")
end
