-- Real Cargo/Clippy diagnostics, not just a configured command or attached LSP.
local evidence = dofile("tests/nvim/ci_evidence.lua")
local record, evidence_path = evidence.open("rust")
local previous_log_level = vim.lsp.log.get_level()
local previous_ra_log, previous_ra_file = vim.env.RA_LOG, vim.env.RA_LOG_FILE
vim.lsp.set_log_level("debug")
vim.env.RA_LOG = "info"
vim.env.RA_LOG_FILE = evidence_path .. ".log"
local root = vim.fn.tempname()
local bufnr
local stage = "toolchain"
local clients = {}
local ok, err = xpcall(function()
	vim.env.RUSTUP_TOOLCHAIN = nil -- Test project-file selection, not a caller override.
	for _, tool in ipairs({ "rustup", "rustc", "cargo", "rustfmt", "cargo-clippy" }) do
		assert(
			vim.fn.exepath(tool):match("/opt/rustup/bin/" .. vim.pesc(tool) .. "$"),
			tool .. " is not a managed rustup proxy"
		)
	end
	local function command(args)
		local result = vim.system(args, { cwd = root, text = true }):wait(30000)
		record("command", { args = args, code = result.code, stdout = result.stdout, stderr = result.stderr })
		assert(result.code == 0, table.concat(args, " ") .. ": " .. (result.stderr or ""))
		return vim.trim(result.stdout)
	end
	vim.fn.mkdir(root .. "/src", "p")
	for _, tool in ipairs({ "rustc", "cargo", "rust-analyzer" }) do
		command({ tool, "--version" })
	end
	command({ "cargo", "clippy", "--version" })
	local active = command({ "rustup", "show", "active-toolchain" }):match("^(%S+)")
	vim.fn.writefile({ "[toolchain]", 'channel = "' .. active .. '"' }, root .. "/rust-toolchain.toml")
	assert(
		command({ "rustup", "show", "active-toolchain" }):find("rust-toolchain.toml", 1, true),
		"Project toolchain was ignored"
	)
	vim.fn.writefile(
		{ "[package]", 'name = "rust-owner-probe"', 'version = "0.0.0"', 'edition = "2024"' },
		root .. "/Cargo.toml"
	)
	vim.fn.writefile({
		"use std::fmt;",
		"fn main() {",
		"    let n = 3_u32;",
		"    let _ = n.clone();",
		"}",
	}, root .. "/src/main.rs")
	vim.env.RUSTUP_AUTO_INSTALL = "0"
	vim.env.CARGO_NET_OFFLINE = "true"
	vim.env.CARGO_TARGET_DIR = root .. "/target"
	command({ "cargo", "fmt", "--check", "--manifest-path", root .. "/Cargo.toml" })
	stage = "attach"
	vim.cmd.edit(vim.fn.fnameescape(root .. "/src/main.rs"))
	bufnr = vim.api.nvim_get_current_buf()
	local last_stage
	assert(
		vim.wait(45000, function()
			clients = vim.lsp.get_clients({ bufnr = bufnr, name = "rust-analyzer" })
			local snapshot = evidence.rust_snapshot(bufnr)
			stage = snapshot.stage
			if stage ~= last_stage then
				record("stage", snapshot)
				last_stage = stage
			end
			return #clients == 1 and clients[1].initialized and snapshot.lint_received == true
		end, 100),
		"Clippy did not deliver the injected lint to Neovim"
	)
	record("clippy-received", evidence.rust_snapshot(bufnr))
	stage = "definition"
	local client = clients[1]
	local opts = LazyVim.opts("rustaceanvim")
	assert(client.config.cmd[1] == opts.server.cmd[1], "Attached analyzer has a different owner")
	assert(not client.config.cmd[1]:find("/rustup/", 1, true), "Analyzer came from the rustup proxy")
	local result = client:request_sync("textDocument/definition", {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
		position = { line = 0, character = 10 },
	}, 15000, bufnr)
	local sysroot = command({ "rustc", "--print", "sysroot" })
	assert(result and not result.err and type(result.result) == "table", "Standard library navigation failed")
	local found = false
	for _, location in ipairs(result.result) do
		local path = vim.uri_to_fname(location.targetUri or location.uri)
		if path:find(sysroot .. "/lib/rustlib/src/rust/library/", 1, true) == 1 then
			found = true
		end
	end
	assert(found, "Analyzer used a different standard-library sysroot")
end, debug.traceback)
record(ok and "passed" or "failed", { stage = stage, error = err, snapshot = bufnr and evidence.rust_snapshot(bufnr) })
if not ok then
	io.stderr:write("Rust failure stage: " .. stage .. "; evidence: " .. evidence_path .. ".jsonl\n")
end
-- Also stop an analyzer that started but never attached to the probe buffer.
clients = vim.lsp.get_clients({ name = "rust-analyzer" })
for _, client in ipairs(clients) do
	client:stop()
end
local stopped = vim.wait(10000, function()
	for _, client in ipairs(clients) do
		if not client:is_stopped() then
			return false
		end
	end
	return true
end, 100)
if not stopped then
	for _, client in ipairs(clients) do
		client:stop(true)
	end
end
record("shutdown", { stopped = stopped })
vim.cmd("silent! %bwipeout!")
if stopped then
	vim.fn.delete(root, "rf")
end
vim.env.RA_LOG, vim.env.RA_LOG_FILE = previous_ra_log, previous_ra_file
vim.lsp.set_log_level(previous_log_level)
assert(ok, err)
assert(stopped, "Rust probe client did not stop")
print("Rust ownership runtime passed: project toolchain, Brew analyzer, rustfmt, Clippy lint, matching sysroot.")
