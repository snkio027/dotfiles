local function fail(message)
	error("COMPLETION_CONTRACT_FAILURE: " .. message, 0)
end

if vim.g.dotfiles_completion_contract_negative then
	fail("COMPLETION_CONTRACT_NEGATIVE_CONTROL")
end

local function assert_equal(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		fail(("%s: expected %s, got %s"):format(label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local lazy_config = require("lazy.core.config")
for _, name in ipairs({ "LuaSnip", "blink.pairs", "nvim-dap-view", "octo.nvim", "snacks.nvim" }) do
	if not lazy_config.plugins[name] then
		fail(("replacement plugin is unavailable: %s"):format(name))
	end
end
for _, name in ipairs({ "mini.snippets", "mini.pairs", "fzf-lua", "nvim-dap-ui", "gh.nvim", "litee.nvim" }) do
	if lazy_config.plugins[name] then
		fail(("retired plugin remains active: %s"):format(name))
	end
end

assert_equal(vim.g.lazyvim_picker, "snacks", "LazyVim picker ownership")
assert_equal(LazyVim.opts("octo.nvim").picker, "snacks", "Octo picker integration")
assert_equal(LazyVim.opts("nvim-dap-view").auto_toggle, true, "DAP view session lifecycle")
assert_equal(LazyVim.opts("blink.pairs").highlights.enabled, false, "Blink pairs rainbow highlights")

local blink_opts = LazyVim.opts("blink.cmp")
assert_equal(blink_opts.snippets.preset, "luasnip", "Blink snippet engine")
assert_equal(blink_opts.keymap.preset, "enter", "LazyVim Blink keymap preset")

require("lazy").load({ plugins = { "LuaSnip", "blink.cmp", "blink.pairs" } })
local blink_config = require("blink.cmp.config")
local luasnip = require("luasnip")

assert_equal(blink_config.completion.list.selection.preselect({}), true, "default Blink preselection")
assert_equal(blink_config.completion.list.selection.auto_insert({}), true, "default Blink preview insertion")
assert_equal(blink_config.completion.trigger.show_in_snippet, true, "default completion inside snippets")
assert_equal(blink_config.snippets.preset, "luasnip", "runtime Blink snippet engine")
assert(require("blink.pairs").library_available(), "Blink pairs native library is unavailable")

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt")
end

local function unlink_snippet()
	if luasnip.in_snippet() then
		luasnip.unlink_current()
	end
end

local snippet_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(snippet_buffer)
vim.bo[snippet_buffer].filetype = "cpp"
vim.bo[snippet_buffer].expandtab = true
vim.bo[snippet_buffer].shiftwidth = 4
vim.bo[snippet_buffer].tabstop = 4
local cpp_if
vim.wait(1000, function()
	for _, snippet in ipairs(luasnip.get_snippets("cpp")) do
		if snippet.trigger == "if" then
			cpp_if = snippet
			return true
		end
	end
	return false
end, 10)
assert(cpp_if, "friendly-snippets C++ if snippet is unavailable")

vim.api.nvim_buf_set_lines(snippet_buffer, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.keymap.set("i", "<F5>", function()
	luasnip.lsp_expand("if ($1) {\n\t$0\n}")
end, { buffer = snippet_buffer })
feed("i    <F5><Esc>")
assert_equal(vim.api.nvim_buf_get_lines(snippet_buffer, 0, -1, false), {
	"    if () {",
	"        ",
	"    }",
}, "friendly-snippets nested C++ if indentation")
unlink_snippet()
vim.api.nvim_buf_delete(snippet_buffer, { force = true })

local pair_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(pair_buffer)
vim.bo[pair_buffer].filetype = "cpp"
vim.api.nvim_buf_set_lines(pair_buffer, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("i(<Esc>")
assert_equal(vim.api.nvim_buf_get_lines(pair_buffer, 0, -1, false), { "()" }, "Blink pair insertion")
vim.api.nvim_buf_set_lines(pair_buffer, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("i()<Esc>")
assert_equal(vim.api.nvim_buf_get_lines(pair_buffer, 0, -1, false), { "()" }, "Blink closing-pair skip")
vim.api.nvim_buf_delete(pair_buffer, { force = true })

print("Completion interaction contract passed: LazyVim defaults, LuaSnip expansion, replacement plugin topology.")
