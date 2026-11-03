local function eq(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual))
end

local function wait_for(predicate, label)
	assert(vim.wait(5000, predicate, 10), label)
end

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt")
end

vim.o.lines = 90
vim.o.columns = 180
require("lazy").load({ plugins = { "nvim-lspconfig", "neotest", "trouble.nvim" } })
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local filename = root .. "/workflow.lua"
vim.fn.writefile({ "first failure", "second failure", "user diagnostic" }, filename)
vim.cmd("noautocmd edit " .. vim.fn.fnameescape(filename))
local buffer = vim.api.nvim_get_current_buf()
local editor = vim.api.nvim_get_current_win()

-- A real in-process LSP client triggers the configured LspAttach/keymap path.
-- Requests never leave this process or start a language-server installer.
local client_id = vim.lsp.start({
	name = "workflow-ui-fixture",
	root_dir = root,
	cmd = function(dispatchers)
		local closing = false
		local request_id = 0
		return {
			request = function(method, _, callback)
				request_id = request_id + 1
				vim.schedule(function()
					if method == "initialize" then
						callback(nil, {
							capabilities = {
								definitionProvider = true,
								referencesProvider = true,
								implementationProvider = true,
								typeDefinitionProvider = true,
								renameProvider = true,
								codeActionProvider = true,
							},
						})
					elseif method == "textDocument/references" then
						callback(nil, {
							{
								uri = vim.uri_from_fname(filename),
								range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 5 } },
							},
						})
					else
						callback(nil, {})
					end
				end)
				return true, request_id
			end,
			notify = function(method)
				if method == "exit" then
					closing = true
					dispatchers.on_exit(0, 0)
				end
				return true
			end,
			is_closing = function()
				return closing
			end,
			terminate = function()
				closing = true
				dispatchers.on_exit(0, 0)
			end,
		}
	end,
}, { bufnr = buffer })
assert(client_id, "fixture LSP did not start")
wait_for(function()
	return vim.fn.maparg("gr", "n", false, true).desc == "References"
end, "real LSP maps did not attach")
eq(vim.fn.maparg("gr", "n", false, true).nowait, 1, "gr keeps immediate references")
for key, description in pairs({
	gd = "Goto Definition",
	gI = "Goto Implementation",
	gy = "Goto T[y]pe Definition",
	["<leader>cr"] = "Rename (inc-rename.nvim)",
	["<leader>ca"] = "Code Action",
}) do
	eq(vim.fn.maparg(key, "n", false, true).desc, description, "documented LSP key " .. key)
end

-- Execute installed maps, intercepting only the picker boundary. No replacement
-- keymaps are installed by this contract and no real GitHub query is sent.
local function picker_key(key, picker)
	if key == "<leader>gS" then
		eq(vim.fn.maparg(key, "n", false, true).desc, "Git Stash", "stash key owner")
	end
	local original = Snacks.picker[picker]
	local called = 0
	Snacks.picker[picker] = function()
		called = called + 1
	end
	feed(key)
	Snacks.picker[picker] = original
	eq(called, 1, "key dispatch " .. key .. " -> " .. picker)
end
picker_key("gd", "lsp_definitions")
picker_key("gr", "lsp_references")
picker_key("gI", "lsp_implementations")
picker_key("gy", "lsp_type_definitions")
picker_key("<leader>sd", "diagnostics")
picker_key("<leader>sD", "diagnostics_buffer")
picker_key("<leader>gs", "git_status")
picker_key("<leader>gd", "git_diff")
picker_key("<leader>gS", "git_stash")
picker_key("<leader>gl", "git_log")
picker_key("<leader>gL", "git_log")
picker_key("<leader>gf", "git_log_file")

local gh = root .. "/gh-fixture"
vim.fn.writefile({ "#!/bin/sh", "printf \" Token scopes: 'repo', 'read:project'\\n\"" }, gh)
vim.fn.setfperm(gh, "rwx------")
LazyVim.opts("octo.nvim").gh_cmd = gh
require("lazy").load({ plugins = { "octo.nvim" } })
picker_key("<leader>gS", "git_stash")
local octo_commands = require("octo.commands")
local original_search = octo_commands.search
local searched = 0
octo_commands.search = function()
	searched = searched + 1
end
feed("<leader>g/")
octo_commands.search = original_search
eq(searched, 1, "Octo search has an independent working key")

local neotest = require("neotest")
assert(neotest.quickfix == nil, "the global quickfix writer must be disabled")
assert(neotest.trouble == nil, "the unscoped Trouble closer must be disabled")
assert(neotest.dotfiles_results, "the owned result consumer must be registered")

-- Keep actual native quickfix, diagnostics, and references windows open while
-- fixture completion events drive the installed consumer and real Trouble UI.
vim.fn.setqflist({}, " ", {
	title = "User grep",
	context = { owner = "user" },
	items = { { filename = filename, lnum = 3, col = 1, text = "user grep result" } },
})
vim.cmd.copen()
local quickfix_window = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(editor)
local namespace = vim.api.nvim_create_namespace("workflow-ui-user")
vim.diagnostic.set(namespace, buffer, {
	{ lnum = 2, col = 0, message = "user diagnostic", severity = vim.diagnostic.severity.WARN },
})
local trouble = require("trouble")
local diagnostics = trouble.open({ mode = "diagnostics", focus = false, auto_close = false })
wait_for(function()
	return diagnostics:is_open()
end, "diagnostics window did not open")
local references = trouble.open({ mode = "lsp_references", focus = false, auto_jump = false, auto_close = false })
wait_for(function()
	return references:is_open()
end, "references window did not open")
local quickfix = vim.fn.getqflist({ all = true })
local late_diagnostics
local preview = require("trouble.view.preview")
local unrelated_preview

local function assert_unrelated()
	assert(vim.api.nvim_win_is_valid(quickfix_window), "test results closed native quickfix")
	assert(diagnostics:is_open(), "test results closed diagnostics")
	assert(references:is_open(), "test results closed references")
	assert(not late_diagnostics or late_diagnostics:is_open(), "test results closed the newest unrelated view")
	if unrelated_preview then
		assert(preview.preview == unrelated_preview, "test results closed the unrelated diagnostic preview")
		assert(vim.api.nvim_win_is_valid(unrelated_preview.win), "diagnostic preview window was closed")
	end
	eq(vim.fn.getqflist({ all = true }), quickfix, "test results changed the user's quickfix")
	eq(vim.api.nvim_get_current_win(), editor, "test results stole editor focus")
end

local Tree = require("neotest.types").Tree
local trees, results = {}, { a = {}, b = {} }
for _, adapter in ipairs({ "a", "b" }) do
	trees[adapter] = Tree.from_list({
		{ id = filename, type = "file", path = filename, name = "workflow", range = { 0, 0, 3, 0 } },
		{ { id = "one", type = "test", path = filename, name = "one", range = { 0, 0, 1, 0 } } },
		{ { id = "two", type = "test", path = filename, name = "two", range = { 1, 0, 2, 0 } } },
	}, function(position)
		return position.id
	end)
end
local client = {
	listeners = {},
	get_position = function(_, _, opts)
		return trees[opts.adapter]
	end,
	get_results = function(_, adapter)
		return results[adapter]
	end,
}
LazyVim.opts("neotest").consumers.dotfiles_results(client)
local function count()
	return #trouble.get_items({ mode = "neotest_results" })
end
local function complete(adapter, partial)
	client.listeners.results(adapter, results[adapter], partial)
end

results.a = {
	one = { status = "failed", errors = { { line = 0, message = "first test failure" } } },
	two = { status = "failed", errors = {} },
}
complete("a", true)
vim.wait(100)
assert(not trouble.is_open({ mode = "neotest_results" }), "partial results opened a panel")
complete("a", false)
wait_for(function()
	return count() == 2
end, "failed tests were not displayed, including the no-error-details fallback")
assert_unrelated()
results.a.one = { status = "passed" }
complete("a", false)
wait_for(function()
	return count() == 1
end, "rerunning one test hid or retained the wrong failures")
results.b.one = { status = "failed", errors = { { line = 0, message = "other adapter failure" } } }
complete("b", false)
wait_for(function()
	return count() == 2
end, "failures from separate adapters were not retained")
results.a.two = { status = "passed" }
complete("a", false)
wait_for(function()
	return count() == 1
end, "one passing adapter erased another adapter's failure")
assert_unrelated()

trouble.close({ mode = "neotest_results" })
feed("<leader>tq")
wait_for(function()
	return count() == 1
end, "the installed test-results key did not reopen the list")
assert_unrelated()

-- Open an unrelated view *after* the failed-test view: an unscoped close would
-- now target this window instead of the test window and must be rejected.
late_diagnostics = trouble.open({ mode = "diagnostics", new = true, focus = false, auto_close = false })
wait_for(function()
	return late_diagnostics:is_open()
end, "newer diagnostics view did not open")
late_diagnostics:preview(assert(late_diagnostics:flatten()[1]))
unrelated_preview = assert(preview.preview, "diagnostic preview did not open")

-- A newer user list also survives the final successful rerun.
vim.fn.setqflist({}, "r", { title = "User build", items = quickfix.items, context = { owner = "new-user-list" } })
quickfix = vim.fn.getqflist({ all = true })
results.b.one = { status = "passed" }
complete("b", false)
wait_for(function()
	return not trouble.is_open({ mode = "neotest_results" })
end, "successful rerun left its own failure panel open")
assert_unrelated()

-- Completion events can arrive in one event-loop turn while a view is opening.
results.a.one = { status = "failed", errors = { { message = "fast failure" } } }
complete("a", false)
results.a.one = { status = "passed" }
complete("a", false)
vim.wait(300)
assert(not trouble.is_open({ mode = "neotest_results" }), "fast failure/success left a stale panel")
assert_unrelated()

-- Closing a focused test view must not let Trouble's WinLeave hook close a
-- diagnostic preview either. Both views preview the same file deliberately.
results.a.one = { status = "failed", errors = { { message = "focused failure" } } }
complete("a", false)
wait_for(function()
	return count() == 1
end, "focused test view did not open")
local owned = require("trouble.view").get({ mode = "neotest_results" })[1].view
vim.api.nvim_set_current_win(owned.win.win)
vim.wait(150)
late_diagnostics:preview(assert(late_diagnostics:flatten()[1]))
unrelated_preview = assert(preview.preview)
results.a.one = { status = "passed" }
complete("a", false)
wait_for(function()
	return not trouble.is_open({ mode = "neotest_results" })
end, "focused successful test view remained open")
assert_unrelated()

-- A preview that belongs to the test view itself is still cleaned up.
preview.close()
unrelated_preview = nil
results.a.one = { status = "failed", errors = { { message = "previewed failure" } } }
complete("a", false)
wait_for(function()
	return count() == 1
end, "previewed test view did not open")
owned = require("trouble.view").get({ mode = "neotest_results" })[1].view
owned:preview(assert(owned:flatten()[1]))
assert(preview.preview and preview.item().source == "dotfiles_tests", "test preview did not open")
results.a.one = { status = "passed" }
complete("a", false)
wait_for(function()
	return not trouble.is_open({ mode = "neotest_results" })
end, "previewed successful test view remained open")
assert(not preview.is_open(), "successful test view left its own preview open")
assert_unrelated()

vim.lsp.stop_client(client_id, true)
references:close()
diagnostics:close()
late_diagnostics:close()
vim.cmd.cclose()
vim.diagnostic.reset(namespace)
vim.fn.delete(root, "rf")
print(
	"Workflow UI contract passed: real key dispatch, independent GitHub search, owned test windows, preserved quickfix."
)
io.stdout:write("WORKFLOW_UI_COMPLETE\n")
