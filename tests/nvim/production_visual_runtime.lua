--- DX-COLOR-003 M5 production C4.4 runtime contract.

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
			fail("C4.4 production visual is missing a concrete foreground for " .. role)
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
	}
	for group, role in pairs(representative_bindings) do
		local actual = vim.api.nvim_get_hl(0, { name = group, link = false })
		assert_eq(
			actual.fg,
			hex_to_rgb(expected_roles[role].fg),
			("runtime binding mismatch: %s -> %s"):format(group, role)
		)
	end

	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local resolved_background = rgb_to_hex(normal.bg)
	assert_eq(resolved_background:lower(), palette.ui.normal_bg:lower(), "runtime resolved the wrong Normal background")

	local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
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

	print(("M5 production C4.4 runtime contract passed against actual Normal.bg %s."):format(resolved_background))
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	io.stderr:write(("\n!!! M5 PRODUCTION VISUAL RUNTIME FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.api.nvim_err_writeln(("M5 PRODUCTION VISUAL RUNTIME FAILURE: %s"):format(tostring(err)))
	vim.cmd("cquit 1")
end
