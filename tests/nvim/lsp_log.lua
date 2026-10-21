-- Exercise the configured binary, not just a string comparison. Logging must
-- stop routine traffic while retaining compiler errors and failure status.
local command = vim.deepcopy(assert(vim.lsp.config.clangd.cmd))
assert(vim.tbl_contains(command, "--log=error"), "CLANGD_LOG_POLICY_MISSING")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local source = root .. "/main.cpp"
local function check(cmd)
	local result = vim.system(vim.list_extend(vim.deepcopy(cmd), { "--check=" .. source }), {
		cwd = root,
		text = true,
	}):wait(15000)
	assert(result.code ~= 124, "clangd log check timed out")
	return result
end
local ok, err = xpcall(function()
	vim.fn.writefile({ "int main() { return 0; }" }, source)
	local quiet = check(command)
	assert(quiet.code == 0, quiet.stderr)
	assert(quiet.stderr == "", "CLANGD_ROUTINE_LOG_NOISE: " .. quiet.stderr)
	local default = check(vim.tbl_filter(function(arg)
		return not arg:match("^%-%-log=")
	end, command))
	assert(default.code == 0 and default.stderr:find("I[", 1, true), "default log noise control did not run")
	vim.fn.writefile({ "int main() { return missing_value; }" }, source)
	local failure = check(command)
	assert(failure.code ~= 0, "invalid C++ incorrectly passed")
	assert(failure.stderr:find("E[", 1, true) and failure.stderr:find("missing_value", 1, true), failure.stderr)
	assert(not failure.stderr:find("I[", 1, true), "error path resumed INFO traffic")
end, debug.traceback)
vim.fn.delete(root, "rf")
assert(ok, err)
print("Clangd log contract passed: routine traces suppressed, real errors retained.")
