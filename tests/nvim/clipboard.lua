-- Platform selection only: never read or overwrite the host clipboard.
local clipboard = require("config.clipboard")
local original = {
	has = vim.fn.has,
	executable = vim.fn.executable,
	exepath = vim.fn.exepath,
	resolve = vim.fn.resolve,
	clipboard = vim.g.clipboard,
	connection = vim.env.SSH_CONNECTION,
	tty = vim.env.SSH_TTY,
	option = vim.o.clipboard,
}
local wsl, available = false, {}
local lookups = 0
vim.fn.has = function(feature)
	assert(feature == "wsl", "unexpected platform detection")
	return wsl and 1 or 0
end
vim.fn.executable = function(command)
	lookups = lookups + 1
	return available[command] and 1 or 0
end
local windows_executable = "/mnt/c/Program Files/Neovim/bin/win32yank.exe"
vim.fn.exepath = function(command)
	assert(command == "win32yank.exe")
	return "/home/user/.local/bin/win32yank.exe"
end
vim.fn.resolve = function(path)
	assert(path == "/home/user/.local/bin/win32yank.exe")
	return windows_executable
end
local function configure(is_wsl, tools, override, connection, tty)
	wsl, available, lookups = is_wsl, tools, 0
	vim.g.clipboard = override
	vim.env.SSH_CONNECTION, vim.env.SSH_TTY = connection, tty
	clipboard.setup()
	assert(vim.o.clipboard == original.option, "clipboard register policy changed")
	return vim.g.clipboard
end
local ok, err = xpcall(function()
	local both = { ["win32yank.exe"] = true, ["powershell.exe"] = true }
	assert(configure(false, both) == nil and lookups == 0, "non-WSL behavior changed")
	assert(configure(true, both, nil, "remote connection") == nil and lookups == 0, "SSH used host clipboard")
	assert(configure(true, both, nil, nil, "/dev/pts/1") == nil and lookups == 0, "SSH_TTY used host clipboard")
	for _, override in ipairs({ false, "osc52", { name = "user-selected" } }) do
		assert(vim.deep_equal(configure(true, both, override), override), "explicit clipboard overwritten")
		assert(lookups == 0)
	end
	assert(configure(true, {}) == nil, "missing interop should retain native detection")
	local yank = configure(true, both, nil, "", "")
	assert(yank and yank.name == "win32yank (WSL)", "WSL_PROVIDER_NOT_SELECTED")
	assert(vim.deep_equal(yank.copy["+"], { windows_executable, "-i", "--crlf" }))
	assert(vim.deep_equal(yank.paste["+"], { windows_executable, "-o", "--lf" }))
	local powershell = configure(true, { ["powershell.exe"] = true })
	assert(powershell.name == "Windows PowerShell (WSL)")
	for _, config in ipairs({ yank, powershell }) do
		assert(config.cache_enabled == 0, "external clipboard changes would be cached")
		assert(vim.deep_equal(config.copy["+"], config.copy["*"]))
		assert(vim.deep_equal(config.paste["+"], config.paste["*"]))
	end
	for _, command in ipairs({ powershell.copy["+"], powershell.paste["+"] }) do
		assert(vim.deep_equal(vim.list_slice(command, 1, 6), {
			"powershell.exe",
			"-NoLogo",
			"-NoProfile",
			"-NonInteractive",
			"-STA",
			"-Command",
		}))
		assert(#command == 7 and command[7]:find("$ErrorActionPreference='Stop'", 1, true))
		assert(command[7]:find("UTF8Encoding", 1, true), "Unicode encoding was left implicit")
	end
	assert(powershell.copy["+"][7]:find("[Console]::In.ReadToEnd()", 1, true), "copy must consume stdin")
	assert(powershell.paste["+"][7]:find("Get-Clipboard -Raw", 1, true), "multiline paste must use Raw")
	assert(powershell.paste["+"][7]:find("[Console]::Write(", 1, true), "paste must not add a newline")
	assert(powershell.paste["+"][7]:find('-replace "`r`n", "`n"', 1, true), "CRLF must become LF")
	clipboard.setup()
	assert(vim.deep_equal(vim.g.clipboard, powershell), "setup is not idempotent")
end, debug.traceback)
vim.fn.has, vim.fn.executable = original.has, original.executable
vim.fn.exepath, vim.fn.resolve = original.exepath, original.resolve
vim.g.clipboard = original.clipboard
vim.env.SSH_CONNECTION, vim.env.SSH_TTY = original.connection, original.tty
assert(ok, err)
print("Clipboard selection contract passed: WSL, Windows helpers, SSH and native fallbacks.")
