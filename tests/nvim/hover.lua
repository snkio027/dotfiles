-- Exercise Noice's real hover formatter, router and NUI windows with a
-- deterministic LSP response; no server or replacement renderer is involved.
require("lazy").load({ plugins = { "noice.nvim" } })
local config = require("noice.config")
-- Contract runners execute before VimEnter, when Noice normally starts.
config.setup(LazyVim.opts("noice.nvim"))
local router = require("noice.message.router")
local views = require("noice.view")
local hover, signature
for _, route in ipairs(config.options.routes) do
	if route.filter.event == "lsp" and route.filter.kind == "hover" then
		hover = router.add(route).view
	elseif route.filter.event == "lsp" and route.filter.kind == "signature" then
		signature = views.get_view(route.view, route.opts)
	end
end
assert(hover and signature, "HOVER_ROUTES_MISSING")
assert(signature._opts.border.style == "none", "HOVER_CHANGED_SIGNATURE_BORDER")
assert(signature._opts.size.max_width == 120, "HOVER_CHANGED_SIGNATURE_WIDTH")

local api = vim.api
local original_win = api.nvim_get_current_win()
local columns, lines = vim.o.columns, vim.o.lines
-- Earlier smoke cases leave build/output splits. Use a separate full-height
-- tab so cursor-relative geometry does not depend on another contract's layout.
vim.cmd.tabnew()
local source_win, scratch = api.nvim_get_current_win(), api.nvim_get_current_buf()
vim.bo[scratch].buftype = "nofile"
vim.bo[scratch].bufhidden = "wipe"
local highlights = {}
for _, name in ipairs({ "Normal", "NormalFloat", "FloatBorder", "NoicePopup", "NoicePopupBorder" }) do
	highlights[name] = api.nvim_get_hl(0, { name = name })
end

local function check_documentation(markdown, expected, expected_width)
	require("noice.lsp.hover").on_hover(nil, {
		contents = { kind = "markdown", value = markdown },
	}, { bufnr = scratch })
	router.update()
	local popup = hover._nui
	assert(popup and popup.winid and api.nvim_win_is_valid(popup.winid), "HOVER_WINDOW_MISSING")
	local border = popup.border
	assert(border and border.winid and api.nvim_win_is_valid(border.winid), "HOVER_BORDER_MISSING")
	local content_config = api.nvim_win_get_config(popup.winid)
	local border_config = api.nvim_win_get_config(border.winid)
	local frame = api.nvim_buf_get_lines(border.bufnr, 0, -1, false)
	assert(frame[1]:match("^╭.*╮$") and frame[#frame]:match("^╰.*╯$"), "HOVER_ROUNDED_BORDER_MISSING")
	-- max_width applies to text; NUI adds two padding cells and one border on
	-- each side. Check actual windows, not just the declarative configuration.
	assert(content_config.width == expected_width and content_config.width <= 90, "HOVER_WIDTH_MISMATCH")
	assert(border_config.width == content_config.width + 6, "HOVER_HORIZONTAL_PADDING_MISMATCH")
	assert(content_config.win == border.winid and content_config.col == 3, "HOVER_CONTENT_INSET_MISMATCH")
	local border_position = api.nvim_win_get_position(border.winid)
	local source_position = api.nvim_win_get_position(source_win)
	assert(border_position[1] == source_position[1] + 1, "HOVER_CURSOR_GAP_MISMATCH")
	assert(vim.wo[popup.winid].wrap and vim.wo[popup.winid].linebreak, "HOVER_WRAP_DISABLED")
	assert(vim.wo[popup.winid].winblend == 0, "HOVER_BECAME_TRANSPARENT")
	local rendered = table.concat(api.nvim_buf_get_lines(popup.bufnr, 0, -1, false), "\n")
	for _, text in ipairs(expected) do
		assert(rendered:find(text, 1, true), "HOVER_CONTENT_TRUNCATED: " .. text)
	end
	assert(api.nvim_get_current_win() == source_win, "HOVER_STOLE_FOCUS")
	assert(vim.deep_equal(api.nvim_win_get_cursor(source_win), { 1, 0 }), "HOVER_MOVED_CURSOR")
	assert(
		vim.deep_equal(api.nvim_buf_get_lines(scratch, 0, -1, false), { "auto result = example();" }),
		"HOVER_EDITED_SOURCE"
	)
	for name, definition in pairs(highlights) do
		assert(vim.deep_equal(api.nvim_get_hl(0, { name = name }), definition), "HOVER_CHANGED_HIGHLIGHT: " .. name)
	end
	require("noice.lsp.docs").on_close()
	router.update()
	assert(not api.nvim_win_is_valid(popup.winid or -1), "HOVER_DID_NOT_CLOSE")
end

local ok, err = xpcall(function()
	vim.o.columns, vim.o.lines = 160, 50
	api.nvim_buf_set_lines(scratch, 0, -1, false, { "auto result = example();" })
	api.nvim_win_set_cursor(source_win, { 1, 0 })
	local declaration = "using example = std::tuple<" .. string.rep("int, ", 30) .. "int>;"
	check_documentation(
		"### type-alias example\n\nprovided by <tuple>\n\n```cpp\n" .. declaration .. "\n```\n\nEnd of documentation.",
		{ "type-alias example", "provided by <tuple>", declaration, "End of documentation." },
		90
	)
	-- Short docs still autosize, including in a smaller terminal.
	vim.o.columns = 80
	check_documentation("Short documentation.", { "Short documentation." }, #"Short documentation.")
end, debug.traceback)

-- Restore even on assertion failure; smoke contracts can share a process.
hover:hide()
api.nvim_win_close(source_win, true)
api.nvim_set_current_win(original_win)
vim.o.columns, vim.o.lines = columns, lines
assert(ok, err)
print(
	"Hover documentation contract passed: rounded frame, padding, 90-column content, unchanged highlights/signature help"
)
