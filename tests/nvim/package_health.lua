-- Theme setup must not initialize a second package manager as a side effect.
local ctp = require("catppuccin")
local options = vim.deepcopy(LazyVim.opts("catppuccin"))
local original_get = vim.pack.get
local original_detect = package.loaded["catppuccin.lib.detect_integrations"]
local calls = 0
vim.pack.get = function()
	calls = calls + 1
	return {}
end
package.loaded["catppuccin.lib.detect_integrations"] = nil
local ok, err = xpcall(function()
	ctp.setup(options)
	assert(calls == 0, "theme setup initialized native package management")
end, debug.traceback)
vim.pack.get = original_get
package.loaded["catppuccin.lib.detect_integrations"] = original_detect
assert(ok, err)
print("Package health contract passed: theme setup avoids native package initialization.")
