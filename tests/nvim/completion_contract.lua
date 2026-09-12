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
local selection = blink_opts.completion.list.selection
assert_equal(selection.preselect, false, "Blink preselection")
assert_equal(selection.auto_insert, false, "Blink preview insertion")
if blink_opts.completion.trigger and blink_opts.completion.trigger.show_in_snippet == false then
	fail("completion inside snippet sessions is disabled")
end
assert_equal(blink_opts.snippets.preset, "luasnip", "Blink snippet engine")
assert_equal(blink_opts.keymap.preset, "enter", "Blink keymap preset")

local tab = blink_opts.keymap["<Tab>"]
assert_equal(type(tab[1]), "function", "Tab active-choice action")
assert_equal({ tab[2], tab[3], tab[4] }, { "select_next", "snippet_forward", "fallback" }, "Tab Insert-mode order")

local shift_tab = blink_opts.keymap["<S-Tab>"]
assert_equal(type(shift_tab[1]), "function", "Shift-Tab active-choice action")
assert_equal(
	{ shift_tab[2], shift_tab[3], shift_tab[4] },
	{ "select_prev", "snippet_backward", "fallback" },
	"Shift-Tab Insert-mode order"
)

local enter = blink_opts.keymap["<CR>"]
assert_equal(type(enter[1]), "function", "Enter active-choice confirmation")
assert_equal(enter[2], "accept", "Enter Insert-mode completion priority")
assert_equal(enter[3], "fallback", "Enter newline fallback")

local columns = blink_opts.completion.menu.draw.columns
assert_equal(columns[#columns], { "source_name" }, "completion source label column")

require("lazy").load({ plugins = { "LuaSnip", "blink.cmp", "blink.pairs" } })
local blink_config = require("blink.cmp.config")
local luasnip = require("luasnip")
assert_equal(blink_config.completion.list.selection.preselect({}), false, "runtime Blink preselection")
assert_equal(blink_config.completion.list.selection.auto_insert({}), false, "runtime Blink preview insertion")
assert_equal(blink_config.completion.trigger.show_in_snippet, true, "runtime completion inside snippet sessions")
assert_equal(blink_config.snippets.preset, "luasnip", "runtime Blink snippet engine")
assert(require("blink.pairs").library_available(), "Blink pairs native library is unavailable")

local snippet_config = require("luasnip.session").config
assert_equal(snippet_config.keep_roots, false, "LuaSnip root history")
assert_equal(snippet_config.link_roots, false, "LuaSnip root linking")
assert_equal(snippet_config.exit_roots, true, "LuaSnip final-tabstop exit")

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt")
end

local function exercise_insert_key(keys, stubs)
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buffer)
	vim.bo[buffer].expandtab = false
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })

	local blink = require("blink.cmp")
	local originals = {}
	for name, replacement in pairs(stubs) do
		originals[name] = blink[name]
		blink[name] = replacement
	end

	local mappings = require("blink.cmp.keymap").get_mappings(blink_config.keymap, "default")
	require("blink.cmp.keymap.apply").keymap_to_current_buffer(mappings)
	feed("i" .. keys .. "<Esc>")

	for name, original in pairs(originals) do
		blink[name] = original
	end
	local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	vim.api.nvim_buf_delete(buffer, { force = true })
	return lines
end

local tab_trace = {}
exercise_insert_key("<Tab>", {
	select_next = function()
		tab_trace[#tab_trace + 1] = "menu"
		return true
	end,
	snippet_forward = function()
		tab_trace[#tab_trace + 1] = "snippet"
		return true
	end,
})
assert_equal(tab_trace, { "menu" }, "Tab menu-first dispatch")

local snippet_trace = {}
exercise_insert_key("<Tab>", {
	select_next = function()
		snippet_trace[#snippet_trace + 1] = "menu"
		return false
	end,
	snippet_forward = function()
		snippet_trace[#snippet_trace + 1] = "snippet"
		return true
	end,
})
assert_equal(snippet_trace, { "menu", "snippet" }, "Tab snippet fallback")

local reverse_trace = {}
exercise_insert_key("<S-Tab>", {
	select_prev = function()
		reverse_trace[#reverse_trace + 1] = "menu"
		return true
	end,
	snippet_backward = function()
		reverse_trace[#reverse_trace + 1] = "snippet"
		return true
	end,
})
assert_equal(reverse_trace, { "menu" }, "Shift-Tab menu-first dispatch")

local tab_fallback = exercise_insert_key("<Tab>", {
	select_next = function()
		return false
	end,
	snippet_forward = function()
		return false
	end,
})
assert_equal(tab_fallback, { "\t" }, "plain Tab fallback")

local enter_fallback = exercise_insert_key("<CR>", {
	accept = function()
		return false
	end,
})
assert_equal(enter_fallback, { "", "" }, "Enter newline fallback")

local enter_accept = exercise_insert_key("<CR>", {
	accept = function()
		return true
	end,
})
assert_equal(enter_accept, { "" }, "Enter selected-item acceptance")

local function unlink_snippet()
	if luasnip.in_snippet() then
		luasnip.unlink_current()
	end
end

local function expand_lsp(body, width, base_indent)
	unlink_snippet()
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buffer)
	vim.bo[buffer].filetype = "cpp"
	vim.bo[buffer].expandtab = true
	vim.bo[buffer].shiftwidth = width
	vim.bo[buffer].tabstop = width
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.keymap.set("i", "<F5>", function()
		luasnip.lsp_expand(body)
	end, { buffer = buffer })
	feed("i" .. string.rep(" ", base_indent) .. "<F5><Esc>")
	local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	unlink_snippet()
	vim.api.nvim_buf_delete(buffer, { force = true })
	return lines
end

local cpp_if = "if (${1:condition}) {\n\t$0\n}"
for _, width in ipairs({ 2, 4 }) do
	local lines = expand_lsp(cpp_if, width, width)
	assert_equal(lines[1], string.rep(" ", width) .. "if (condition) {", ("if opening at shiftwidth=%d"):format(width))
	assert_equal(lines[2], string.rep(" ", width * 2), ("if body indentation at shiftwidth=%d"):format(width))
	assert_equal(lines[3], string.rep(" ", width) .. "}", ("if closing indentation at shiftwidth=%d"):format(width))
end

local reverse
for _, snippet in ipairs(luasnip.get_snippets("cpp")) do
	if snippet.trigger == "forr" and snippet.name == "Safe reverse iterator loop" then
		reverse = snippet
		break
	end
end
if not reverse then
	fail("the C++ forr override is unavailable")
end
assert_equal(reverse.priority, 2000, "C++ forr override priority")

local reverse_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(reverse_buffer)
vim.bo[reverse_buffer].filetype = "cpp"
vim.bo[reverse_buffer].expandtab = true
vim.bo[reverse_buffer].shiftwidth = 4
vim.bo[reverse_buffer].tabstop = 4
vim.api.nvim_buf_set_lines(reverse_buffer, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.keymap.set("i", "<F5>", function()
	luasnip.snip_expand(reverse)
end, { buffer = reverse_buffer })
feed("i<F5><Esc>")
local reverse_lines = vim.api.nvim_buf_get_lines(reverse_buffer, 0, -1, false)
assert(reverse_lines[1]:find(".rbegin()", 1, true), "C++ forr override is missing rbegin")
assert(reverse_lines[1]:find(".rend()", 1, true), "C++ forr override is missing rend")
assert(not reverse_lines[1]:find("size_t", 1, true), "unsafe unsigned reverse loop is active")
assert_equal(reverse_lines[2], "    ", "C++ forr body indentation")
unlink_snippet()
vim.api.nvim_buf_delete(reverse_buffer, { force = true })

local choice_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(choice_buffer)
vim.api.nvim_buf_set_lines(choice_buffer, 0, -1, false, { "" })
local choice = luasnip.s("", { luasnip.c(1, { luasnip.t("first"), luasnip.t("second") }), luasnip.i(0) })
local mappings = require("blink.cmp.keymap").get_mappings(blink_config.keymap, "default")
require("blink.cmp.keymap.apply").keymap_to_current_buffer(mappings)
luasnip.snip_expand(choice)
local mapped_tab = vim.fn.maparg("<Tab>", "i", false, true)
local mapped_enter = vim.fn.maparg("<CR>", "i", false, true)
assert_equal(type(mapped_tab.callback), "function", "runtime Tab callback")
assert_equal(type(mapped_enter.callback), "function", "runtime Enter callback")
mapped_tab.callback()
assert_equal(vim.api.nvim_buf_get_lines(choice_buffer, 0, -1, false), { "second" }, "LuaSnip choice cycling")
mapped_enter.callback()
assert_equal(vim.api.nvim_buf_get_lines(choice_buffer, 0, -1, false), { "second" }, "LuaSnip choice confirmation")
assert(not luasnip.in_snippet(), "LuaSnip session remained active after the final tabstop")
assert_equal(vim.api.nvim_win_get_cursor(0), { 1, 5 }, "LuaSnip final cursor")
feed("<Esc>")
vim.api.nvim_buf_delete(choice_buffer, { force = true })

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

print(
	"Completion interaction contract passed: explicit selection, menu-first Tab, Enter confirmation, adaptive snippets."
)
