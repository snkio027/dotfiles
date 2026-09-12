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

local function find_snippet(snippets, prefix)
	for _, snippet in ipairs(snippets) do
		if snippet.prefix == prefix then
			return snippet
		end
	end
end

local blink_opts = LazyVim.opts("blink.cmp")
local selection = blink_opts.completion.list.selection
assert_equal(selection.preselect, false, "Blink preselection")
assert_equal(selection.auto_insert, false, "Blink preview insertion")
if blink_opts.completion.trigger and blink_opts.completion.trigger.show_in_snippet == false then
	fail("completion inside snippet sessions is disabled")
end
assert_equal(blink_opts.keymap.preset, "enter", "Blink keymap preset")
assert_equal({ unpack(blink_opts.keymap["<Tab>"], 2) }, { "select_next", "snippet_forward", "fallback" }, "Tab order")
assert_equal(
	{ unpack(blink_opts.keymap["<S-Tab>"], 2) },
	{ "select_prev", "snippet_backward", "fallback" },
	"Shift-Tab order"
)
assert_equal({ unpack(blink_opts.keymap["<CR>"], 2) }, { "accept", "fallback" }, "Enter order")

local columns = blink_opts.completion.menu.draw.columns
assert_equal(columns[#columns], { "source_name" }, "completion source label column")

require("lazy").load({ plugins = { "mini.snippets", "blink.cmp" } })
local blink_config = require("blink.cmp.config")
assert_equal(blink_config.completion.list.selection.preselect({}), false, "runtime Blink preselection")
assert_equal(blink_config.completion.list.selection.auto_insert({}), false, "runtime Blink preview insertion")
assert_equal(blink_config.completion.trigger.show_in_snippet, true, "runtime completion inside snippet sessions")
assert_equal(MiniSnippets.config.mappings.stop, "<C-c>", "explicit snippet cancellation")

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
assert_equal(tab_trace, { "menu" }, "Tab menu priority")

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
assert_equal(reverse_trace, { "menu" }, "Shift-Tab menu priority")

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

local function stop_all_sessions()
	while MiniSnippets.session.get(false) do
		MiniSnippets.session.stop()
	end
end

local function native_choice_scenario(keys)
	stop_all_sessions()
	local previous_completeopt = vim.o.completeopt
	vim.o.completeopt = "menu,menuone,noselect"

	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buffer)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })
	local mappings = require("blink.cmp.keymap").get_mappings(blink_config.keymap, "default")
	require("blink.cmp.keymap.apply").keymap_to_current_buffer(mappings)

	local observation = { steps = {} }
	vim.keymap.set("i", "<F5>", function()
		MiniSnippets.default_insert({ body = "${1|first,second|}$0" })
	end, { buffer = buffer })
	vim.keymap.set("i", "<F6>", function()
		if observation.initial_selected == nil then
			local initial = vim.fn.complete_info({ "selected", "items" })
			observation.initial_selected = initial.selected
			observation.words = vim.tbl_map(function(item)
				return item.word
			end, initial.items)
			return
		end
		if vim.fn.pumvisible() == 1 and vim.fn.complete_info({ "selected" }).selected >= 0 then
			-- Headless feedkeys drains a whole queue without the UI loop boundary
			-- that normally dispatches TextChangedP after a native choice changes.
			vim.api.nvim_exec_autocmds("TextChangedP", { buffer = buffer })
		end
		observation.steps[#observation.steps + 1] = {
			key = keys[#observation.steps + 1],
			selected = vim.fn.complete_info({ "selected" }).selected,
			lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
			cursor = vim.api.nvim_win_get_cursor(0),
		}
	end, { buffer = buffer })

	local sequence = "i<F5><F6>"
	for _, lhs in ipairs(keys) do
		sequence = sequence .. lhs .. "<F6>"
	end
	feed(sequence .. "<Esc>")
	if observation.initial_selected == nil then
		fail("mini.snippets did not expose its native choice menu")
	end

	stop_all_sessions()
	vim.o.completeopt = previous_completeopt
	vim.api.nvim_buf_delete(buffer, { force = true })
	return observation
end

local choice_cycle = native_choice_scenario({ "<Tab>", "<Tab>", "<S-Tab>", "<CR>" })
assert_equal(choice_cycle.initial_selected, -1, "native choice starts without a selection")
assert_equal(choice_cycle.words, { "first", "second" }, "native choice candidates")
assert_equal(choice_cycle.steps[1].selected, 0, "Tab selects the first native choice")
assert_equal(choice_cycle.steps[1].lines, { "first" }, "first native choice text")
assert_equal(choice_cycle.steps[2].selected, 1, "second Tab selects the next native choice")
assert_equal(choice_cycle.steps[2].lines, { "second" }, "second native choice text")
assert_equal(choice_cycle.steps[3].selected, 0, "Shift-Tab selects the previous native choice")
assert_equal(choice_cycle.steps[3].lines, { "first" }, "previous native choice text")
assert_equal(choice_cycle.steps[4].selected, -1, "selected native choice Enter closes completion")
assert_equal(choice_cycle.steps[4].lines, { "first" }, "Enter accepts a selected native choice without a newline")
assert_equal(choice_cycle.steps[4].cursor, { 1, 5 }, "selected native choice Enter cursor")

local choice_enter = native_choice_scenario({ "<CR>" })
assert_equal(choice_enter.initial_selected, -1, "native choice Enter starts without a selection")
assert_equal(choice_enter.steps[1].selected, -1, "unselected native choice Enter does not select a candidate")
assert_equal(choice_enter.steps[1].lines, { "", "first" }, "unselected native choice Enter preserves newline")
assert_equal(choice_enter.steps[1].cursor, { 2, 0 }, "unselected native choice Enter cursor")

local choice_reverse = native_choice_scenario({ "<S-Tab>", "<CR>" })
assert_equal(choice_reverse.steps[1].selected, 1, "Shift-Tab initially selects the last native choice")
assert_equal(choice_reverse.steps[1].lines, { "second" }, "last native choice text")
assert_equal(choice_reverse.steps[2].selected, -1, "reverse-selected native choice Enter closes completion")
assert_equal(choice_reverse.steps[2].lines, { "second" }, "Enter accepts the reverse-selected native choice")
assert_equal(choice_reverse.steps[2].cursor, { 1, 6 }, "reverse-selected native choice Enter cursor")

local mini_opts = LazyVim.opts("mini.snippets")
local prepared = MiniSnippets.default_prepare(mini_opts.snippets, {
	context = { buf_id = 0, lang = "cpp" },
})
local reverse = find_snippet(prepared, "forr")
if not reverse then
	fail("the C++ forr override is unavailable")
end
if reverse.body:find("size_t", 1, true) or reverse.body:find(">= 0", 1, true) then
	fail("the unsafe unsigned reverse-loop snippet is still active")
end
if not reverse.body:find(".rbegin()", 1, true) or not reverse.body:find(".rend()", 1, true) then
	fail("the C++ forr override is not iterator based")
end

local function expand_with_shiftwidth(width)
	stop_all_sessions()
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buffer)
	vim.bo[buffer].filetype = "cpp"
	vim.bo[buffer].expandtab = true
	vim.bo[buffer].shiftwidth = width
	vim.bo[buffer].tabstop = width
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	MiniSnippets.default_insert(vim.deepcopy(reverse))
	vim.fn.feedkeys("", "x")
	if not vim.wait(1000, function()
		return MiniSnippets.session.get(false) ~= nil
	end, 10) then
		fail("snippet session did not start")
	end

	local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	assert_equal(lines[2], string.rep(" ", width), ("snippet indentation at shiftwidth=%d"):format(width))

	MiniSnippets.session.jump("next")
	vim.fn.feedkeys("", "x")
	if not vim.wait(1000, function()
		return (MiniSnippets.session.get(false) or {}).cur_tabstop == "2"
	end, 10) then
		fail("snippet session did not advance to its second tabstop")
	end
	MiniSnippets.session.jump("next")
	vim.fn.feedkeys("", "x")
	if not vim.wait(1000, function()
		return MiniSnippets.session.get(false) == nil
	end, 10) then
		fail("snippet session remained active after reaching its final tabstop")
	end

	vim.api.nvim_buf_delete(buffer, { force = true })
end

expand_with_shiftwidth(2)
expand_with_shiftwidth(4)

print(
	"Completion interaction contract passed: explicit selection, menu-first Tab, Enter confirmation, adaptive snippets."
)
