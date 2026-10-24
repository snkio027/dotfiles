-- Exercise real Blink and native diagnostic windows with deterministic input.
-- Selection/acceptance semantics are covered separately by completion_contract.
require("lazy").load({ plugins = { "blink.cmp", "nvim-lspconfig" } })
local api = vim.api
local menu = require("blink.cmp.completion.windows.menu")
local docs = require("blink.cmp.completion.windows.documentation")
local config = require("blink.cmp.config")
local original_win = api.nvim_get_current_win()
local columns, lines = vim.o.columns, vim.o.lines
vim.cmd.tabnew()
local source_win, source_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
vim.bo[source_buf].buftype = "nofile"
vim.bo[source_buf].bufhidden = "wipe"
local source = "    parse"
api.nvim_buf_set_lines(source_buf, 0, -1, false, { source })
api.nvim_win_set_cursor(source_win, { 1, #source - 1 })
local diagnostic_ns = api.nvim_create_namespace("dotfiles.float_contract")
local diagnostic_win
local highlights = {}
for _, name in ipairs({ "NormalFloat", "FloatBorder", "BlinkCmpMenu", "BlinkCmpDoc", "BlinkCmpDocBorder" }) do
	highlights[name] = api.nvim_get_hl(0, { name = name })
end

local function check_frame(win, label, max_width)
	assert(win and api.nvim_win_is_valid(win), label .. "_WINDOW_MISSING")
	local options = api.nvim_win_get_config(win)
	assert(type(options.border) == "table", label .. "_BORDER_MISMATCH")
	local border = vim.tbl_map(function(cell)
		return type(cell) == "table" and cell[1] or cell
	end, options.border)
	assert(
		vim.deep_equal(border, { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }),
		label .. "_BORDER_MISMATCH"
	)
	assert(options.width <= max_width, label .. "_WIDTH_EXCEEDED")
	local position = api.nvim_win_get_position(win)
	-- Native float positions include the border's top-left cell.
	local rect = { top = position[1], left = position[2] }
	rect.bottom, rect.right = rect.top + options.height + 2, rect.left + options.width + 2
	assert(rect.top >= 0 and rect.left >= 0 and rect.right <= vim.o.columns, label .. "_OFFSCREEN")
	assert(rect.bottom <= vim.o.lines, label .. "_OFFSCREEN")
	return rect
end

local ok, err = xpcall(function()
	assert(config.completion.documentation.auto_show, "COMPLETION_DOC_AUTO_SHOW_CHANGED")
	assert(config.completion.documentation.auto_show_delay_ms == 200, "COMPLETION_DOC_DELAY_CHANGED")
	assert(not config.signature.enabled, "SECOND_SIGNATURE_OWNER_ENABLED")
	local context = {
		id = 1,
		timestamp = vim.uv.now(),
		bufnr = source_buf,
		cursor = { 1, #source - 1 },
		line = source,
		bounds = { start_col = 5, length = 5 },
		mode = "default",
		get_line = function()
			return source
		end,
		get_cursor = function()
			return api.nvim_win_get_cursor(source_win)
		end,
	}
	local documentation = "Parses a document. " .. string.rep("Long parameter documentation. ", 12) .. "End of docs."
	local items = {
		{
			label = "parse_file",
			kind = 3,
			source_id = "float_contract",
			source_name = "Contract",
			documentation = { kind = "markdown", value = documentation },
		},
		{ label = "parse_text", kind = 3, source_id = "float_contract", source_name = "Contract" },
	}
	for _, width in ipairs({ 180, 80 }) do
		vim.o.columns, vim.o.lines = width, 50
		menu.open_with_items(context, items)
		menu.set_selected_item_idx(1)
		docs.show_item(context, items[1])
		assert(
			vim.wait(1000, function()
				return docs.win:is_open()
			end),
			"COMPLETION_DOC_TIMEOUT"
		)
		vim.cmd.redraw()
		local menu_rect = check_frame(menu.win:get_win(), "COMPLETION_MENU", width - 2)
		local doc_rect = check_frame(docs.win:get_win(), "COMPLETION_DOC", 80)
		-- Blink may share one border cell between adjacent frames. Neither
		-- frame may cover the other's text; retain its native placement logic.
		assert(
			menu_rect.right - 1 <= doc_rect.left
				or doc_rect.right - 1 <= menu_rect.left
				or menu_rect.bottom - 1 <= doc_rect.top
				or doc_rect.bottom - 1 <= menu_rect.top,
			"COMPLETION_WINDOWS_OVERLAP: " .. vim.inspect({ menu_rect, doc_rect })
		)
		local rendered = table.concat(api.nvim_buf_get_lines(docs.win:get_buf(), 0, -1, false), "\n")
		assert(rendered:find(documentation, 1, true), "COMPLETION_DOC_TRUNCATED")
		assert(api.nvim_win_get_cursor(menu.win:get_win())[1] == 1, "COMPLETION_SELECTION_CHANGED")
		menu.close()
		assert(not docs.win:is_open(), "COMPLETION_DOC_LEFT_OPEN")
	end
	vim.o.columns = 160
	local message = "A diagnostic with context. " .. string.rep("Details of the problem. ", 12) .. "End of diagnostic."
	vim.diagnostic.set(diagnostic_ns, source_buf, {
		{ lnum = 0, col = 4, message = message, severity = vim.diagnostic.severity.ERROR },
	})
	local diagnostic_buf
	diagnostic_buf, diagnostic_win = vim.diagnostic.open_float(source_buf, { scope = "buffer" })
	check_frame(diagnostic_win, "DIAGNOSTIC", 90)
	local rendered = table.concat(api.nvim_buf_get_lines(diagnostic_buf, 0, -1, false), "\n")
	assert(rendered:find("End of diagnostic.", 1, true), "DIAGNOSTIC_TRUNCATED")
	assert(api.nvim_get_current_win() == source_win, "FLOAT_STOLE_FOCUS")
	assert(vim.deep_equal(api.nvim_win_get_cursor(source_win), { 1, #source - 1 }), "FLOAT_MOVED_CURSOR")
	assert(vim.deep_equal(api.nvim_buf_get_lines(source_buf, 0, -1, false), { source }), "FLOAT_EDITED_SOURCE")
	for name, definition in pairs(highlights) do
		assert(vim.deep_equal(api.nvim_get_hl(0, { name = name }), definition), "FLOAT_CHANGED_HIGHLIGHT: " .. name)
	end
end, debug.traceback)

menu.close()
docs.close()
vim.diagnostic.reset(diagnostic_ns, source_buf)
if diagnostic_win and api.nvim_win_is_valid(diagnostic_win) then
	api.nvim_win_close(diagnostic_win, true)
end
api.nvim_win_close(source_win, true)
api.nvim_set_current_win(original_win)
vim.o.columns, vim.o.lines = columns, lines
assert(ok, err)
print("Completion/diagnostic window contract passed: rounded frames, bounded nonoverlapping docs, unchanged source")
