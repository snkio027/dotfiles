-- Run with the existing run_contract.lua in the isolated candidate only.
-- The CLI is a local PTY byte recorder, not a second AI agent.
local spec = dofile("experiments/ai-workbench/sidekick.lua")[1]
local function tab_maps()
	local result = {}
	for _, mode in ipairs({ "n", "i", "s", "x" }) do
		result[mode] = vim.fn.maparg("<Tab>", mode, false, true)
	end
	return result
end
local before = tab_maps()
require("lazy").load({ plugins = { "sidekick.nvim" } })
local config = require("sidekick.config")
assert(config.nes.enabled == false and config.cli.mux.enabled == false)
assert(vim.deep_equal(before, tab_maps()), "Sidekick changed Tab")
assert(not package.loaded["sidekick.nes"], "NES was loaded")
assert(vim.deep_equal(config.get_tool("codex").cmd, spec.opts.cli.tools.codex.cmd))

-- Exercise the real Sidekick terminal and Neovim paste path. Bracketed paste
-- may contain newlines, but no Enter may occur outside a paste frame.
config.cli.tools.codex.cmd = {
	"python3",
	"-u",
	"-c",
	[[
import os, tty
tty.setraw(0)
os.write(1, b'\x1b[?2004hReady\r\nLocal\r\nPTY\r\nRecorder\r\n')
while True:
    data = os.read(0, 65536)
    if not data:
        break
    os.write(1, b'\r\nRX:' + data.hex().encode() + b':END\r\n')
]],
}
local cli = require("sidekick.cli")
local source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(source)
vim.api.nvim_buf_set_name(source, vim.fn.stdpath("cache") .. "/context.txt")
vim.fn.writefile({ "saved version" }, vim.api.nvim_buf_get_name(source))
vim.api.nvim_buf_set_lines(source, 0, -1, false, { "first line", "UNSAVED_SELECTED_CODE", "last line" })
local source_win = vim.api.nvim_get_current_win()
local diagnostic_ns = vim.api.nvim_create_namespace("sidekick-trial-test")
vim.diagnostic.set(diagnostic_ns, source, { { lnum = 1, col = 0, message = "CURRENT_FILE_ERROR", severity = 1 } })
local other = vim.api.nvim_create_buf(true, false)
vim.diagnostic.set(diagnostic_ns, other, { { lnum = 0, col = 0, message = "OTHER_FILE_ERROR", severity = 1 } })

spec.keys[1][2]()
local state
assert(
	vim.wait(10000, function()
		state = require("sidekick.cli.state").get({ name = "codex", attached = true })[1]
		return state and state.terminal
	end, 20),
	"Codex entry did not open a terminal"
)
local terminal = state.terminal
local function received()
	local screen = table.concat(vim.api.nvim_buf_get_lines(terminal.buf, 0, -1, false), "")
	local raw = ""
	for hex in screen:gmatch("RX:(%x+):END") do
		raw = raw .. hex:gsub("..", function(byte)
			return string.char(tonumber(byte, 16))
		end)
	end
	return raw
end
local function wait_for(text)
	assert(
		vim.wait(10000, function()
			return received():find(text, 1, true) ~= nil
		end, 20),
		"PTY did not receive " .. text
	)
end
local function edit_source()
	vim.cmd.stopinsert()
	vim.api.nvim_set_current_win(source_win)
	vim.api.nvim_win_set_cursor(source_win, { 2, 0 })
end
edit_source()
spec.keys[2][2]()
wait_for("context.txt")
assert(received():find(":L2", 1, true), "current position missing")
edit_source()
vim.cmd.normal({ "V", bang = true })
spec.keys[2][2]()
wait_for("UNSAVED_SELECTED_CODE")
edit_source()
spec.keys[3][2]()
wait_for("CURRENT_FILE_ERROR")
assert(not received():find("OTHER_FILE_ERROR", 1, true), "diagnostics leaked across buffers")
assert(vim.bo[source].modified, "context transfer saved the source buffer")
-- Let a mistakenly queued submit reach the recorder before checking it.
vim.wait(500, function()
	return false
end, 20)
local raw = received()
local _, pastes = raw:gsub("\27%[200~.-\27%[201~", "")
assert(pastes == 3, "expected three bracketed prompt drafts")
assert(raw:gsub("\27%[200~.-\27%[201~", "") == "", "unexpected input outside paste (auto-submit)")
vim.fn.jobstop(terminal.job)
print("Sidekick candidate: position, unsaved selection, current-file diagnostics, no auto-submit PASS")
