--- DX Semantic Color System & Neovim Contract Test Runner
--- Ensures reliable CI failure propagation via xpcall + :cquit 1.

vim.opt.swapfile = false

local args = vim.fn.argv()
-- An explicit path does not open the test itself as a Lua editing buffer (and
-- accidentally start lua_ls). Keep argv support for existing contract callers.
local test_file = vim.g.dotfiles_contract_file

for _, arg in ipairs(test_file and {} or args) do
	if arg:match("%.lua$") and arg ~= "tests/nvim/run_contract.lua" then
		test_file = arg
		break
	end
end

if not test_file or test_file == "" then
	io.stderr:write("RUN_CONTRACT_ERROR: No test lua file specified in argv\n")
	vim.api.nvim_err_writeln("RUN_CONTRACT_ERROR: No test lua file specified in argv")
	vim.cmd("cquit 1")
end

local ok, err = xpcall(function()
	dofile(test_file)
end, debug.traceback)

if not ok then
	io.stderr:write(("\n!!! TEST CONTRACT FAILURE [%s] !!!\n%s\n"):format(test_file, tostring(err)))
	vim.api.nvim_err_writeln(("\n!!! TEST CONTRACT FAILURE [%s] !!!\n%s\n"):format(test_file, tostring(err)))
	vim.cmd("cquit 1")
end

vim.cmd("qall!")
