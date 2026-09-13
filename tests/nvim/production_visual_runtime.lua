--- DX-COLOR-003 E production visual runtime contract.

local function main()
	local function fail(message)
		error("PRODUCTION_VISUAL_RUNTIME_FAILURE: " .. message, 2)
	end

	local function assert_eq(actual, expected, message)
		if actual ~= expected then
			fail(
				(message or "assertion failed")
					.. (" (expected %s, got %s)"):format(vim.inspect(expected), vim.inspect(actual))
			)
		end
	end

	local function hex_to_rgb(hex)
		return tonumber(hex:gsub("^#", ""), 16)
	end

	local function rgb_to_hex(rgb)
		if type(rgb) ~= "number" then
			fail("resolved highlight color is unavailable")
		end
		return ("#%06X"):format(rgb)
	end

	local colorscheme = vim.g.colors_name
	if colorscheme ~= "catppuccin" and colorscheme ~= "catppuccin-mocha" then
		fail(("Catppuccin production colorscheme is not active: %s"):format(vim.inspect(colorscheme)))
	end

	local theme = require("theme")
	if theme.default_profile ~= nil or theme.resolve_profile ~= nil or theme.active_profile ~= nil then
		fail("runtime profile-selection surface still exists")
	end

	local catppuccin = require("catppuccin.palettes").get_palette("mocha")
	if type(catppuccin) ~= "table" then
		fail("Catppuccin Mocha palette is unavailable")
	end
	local palette = require("theme.palette").resolve(catppuccin)
	local visual = require("theme.visual.c4")
	local domain = require("theme.domain")
	local expected_roles = visual.roles(palette)
	local actual_roles = {}

	for role in pairs(domain.roles) do
		local expected = expected_roles[role]
		local actual = vim.api.nvim_get_hl(0, { name = role, link = false })
		if type(expected) ~= "table" or type(expected.fg) ~= "string" then
			fail("E production visual is missing a concrete foreground for " .. role)
		end
		assert_eq(actual.fg, hex_to_rgb(expected.fg), "runtime foreground mismatch for " .. role)
		for _, attribute in ipairs({ "bold", "italic", "underline", "undercurl", "strikethrough", "nocombine" }) do
			assert_eq(
				actual[attribute] == true,
				expected[attribute] == true,
				("runtime attribute mismatch for %s.%s"):format(role, attribute)
			)
		end
		actual_roles[role] = { fg = rgb_to_hex(actual.fg) }
	end

	local representative_bindings = {
		["@keyword"] = "DxKeyword",
		["@keyword.function"] = "DxFunctionKeyword",
		["@function"] = "DxCallable",
		["@type"] = "DxType",
		["@type.builtin"] = "DxBuiltin",
		["@variable"] = "DxVariable",
		["@variable.member"] = "DxMember",
		["@variable.parameter"] = "DxParameter",
		["@operator"] = "DxOperator",
		["@punctuation.bracket"] = "DxPunctuation",
		["@comment"] = "DxComment",
		["@comment.documentation"] = "DxDocComment",
		["@lsp.type.variable"] = "DxVariable",
		["@lsp.type.property"] = "DxMember",
		["BlinkCmpKindFunction"] = "DxCallable",
		["BlinkCmpKindMethod"] = "DxCallable",
		["BlinkCmpKindConstructor"] = "DxCallable",
		["BlinkCmpKindClass"] = "DxType",
		["BlinkCmpKindStruct"] = "DxType",
		["BlinkCmpKindInterface"] = "DxType",
		["BlinkCmpKindEnum"] = "DxType",
		["BlinkCmpKindTypeParameter"] = "DxType",
		["BlinkCmpKindField"] = "DxMember",
		["BlinkCmpKindProperty"] = "DxMember",
		["BlinkCmpKindModule"] = "DxNamespace",
		["BlinkCmpKindSnippet"] = "DxMeta",
		["BlinkCmpKindMacro"] = "DxMeta",
		["BlinkCmpKindVariable"] = "DxVariable",
		["BlinkCmpKindValue"] = "DxVariable",
		["BlinkCmpKindText"] = "DxVariable",
	}
	local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
	local evidence = dofile(repo_root .. "/tests/nvim/highlight_evidence.lua")
	for group, role in pairs(representative_bindings) do
		local actual = vim.api.nvim_get_hl(0, { name = group, link = false })
		evidence.assert_role(group, role, actual.fg)
		assert_eq(
			actual.fg,
			hex_to_rgb(expected_roles[role].fg),
			("runtime binding mismatch: %s -> %s"):format(group, role)
		)
	end

	-- Decorative UI colors are intentionally independent of the E source palette.
	local preserved_ui = {
		RenderMarkdownQuote = { fg = "#BB9AF7" },
		RenderMarkdownH1 = { fg = "#BB9AF7", bold = true },
		RenderMarkdownHint = { fg = "#BB9AF7" },
		RenderMarkdownH3 = { fg = "#2AC3DE", bold = true },
		-- Catppuccin's Neotest integration supplies bold in both base and E runtime.
		NeotestMarked = { fg = "#F09A6C", bold = true },
		DapBreakpointCondition = { fg = "#F09A6C" },
		RenderMarkdownCodeInline = { fg = "#F09A6C" },
	}
	for group, expected in pairs(preserved_ui) do
		local actual = vim.api.nvim_get_hl(0, { name = group, link = false })
		assert_eq(actual.fg, hex_to_rgb(expected.fg), "E_UI_PRESERVATION: foreground drift for " .. group)
		assert_eq(actual.bold == true, expected.bold == true, "E_UI_PRESERVATION: bold drift for " .. group)
	end
	assert_eq(
		vim.api.nvim_get_hl(0, { name = "RenderMarkdownCodeInline", link = false }).bg,
		nil,
		"E_UI_PRESERVATION: inline code background must remain unset"
	)
	for _, kind in ipairs({ "Keyword", "File", "Folder" }) do
		assert_eq(
			vim.api.nvim_get_hl(0, { name = "BlinkCmpKind" .. kind, link = false }).fg,
			hex_to_rgb(palette.ui.subtext0),
			"E_UI_PRESERVATION: neutral Blink kind changed: " .. kind
		)
	end

	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local resolved_background = rgb_to_hex(normal.bg)
	assert_eq(resolved_background:lower(), palette.ui.normal_bg:lower(), "runtime resolved the wrong Normal background")

	local c4_contract = dofile(repo_root .. "/tests/nvim/visual_contracts/c4.lua")
	c4_contract.verify({
		palette = palette,
		roles = actual_roles,
		graph = {
			DiagnosticUnderlineError = vim.api.nvim_get_hl(0, { name = "DiagnosticUnderlineError", link = false }),
			DiagnosticUnderlineWarn = vim.api.nvim_get_hl(0, { name = "DiagnosticUnderlineWarn", link = false }),
		},
		domain = domain,
		host_colors = catppuccin,
		resolved_background = resolved_background,
	})

	print(("E production visual runtime contract passed against actual Normal.bg %s."):format(resolved_background))
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	io.stderr:write(("\n!!! E PRODUCTION VISUAL RUNTIME FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.api.nvim_err_writeln(("E PRODUCTION VISUAL RUNTIME FAILURE: %s"):format(tostring(err)))
	vim.cmd("cquit 1")
end
