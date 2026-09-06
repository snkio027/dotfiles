--- DX-COLOR-004 M1 TokyoNight Storm host runtime contract.

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

	assert_eq(vim.g.colors_name, "tokyonight-storm", "TokyoNight Storm production host is not active")

	local theme = require("theme")
	if theme.default_profile ~= nil or theme.resolve_profile ~= nil or theme.active_profile ~= nil then
		fail("runtime profile-selection surface must remain absent")
	end

	local storm = require("tokyonight.colors").setup({ style = "storm" })
	local palette = require("theme.palette").resolve(storm)
	local visual = require("theme.visual.c4")
	local domain = require("theme.domain")
	local expected_roles = visual.roles(palette)
	local actual_roles = {}

	for role in pairs(domain.roles) do
		local expected = expected_roles[role]
		local actual = vim.api.nvim_get_hl(0, { name = role, link = false })
		if type(expected) ~= "table" or type(expected.fg) ~= "string" then
			fail("Storm semantic projection is missing a concrete foreground for " .. role)
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
	assert_eq(normal.bg, hex_to_rgb(storm.bg), "TokyoNight Storm does not own Normal.bg")
	assert_eq(normal.fg, hex_to_rgb(storm.fg), "TokyoNight Storm does not own Normal.fg")
	assert_eq(
		vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }).bg,
		hex_to_rgb(storm.bg_highlight),
		"TokyoNight Storm does not own CursorLine"
	)
	assert_eq(
		vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false }).fg,
		hex_to_rgb(storm.orange),
		"TokyoNight Storm does not own CursorLineNr"
	)
	assert_eq(
		vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg,
		hex_to_rgb(storm.bg_dark),
		"TokyoNight Storm does not own floating surfaces"
	)
	assert_eq(
		vim.api.nvim_get_hl(0, { name = "Pmenu", link = false }).bg,
		hex_to_rgb(storm.bg_dark),
		"TokyoNight Storm does not own completion surfaces"
	)

	local diagnostic_error = vim.api.nvim_get_hl(0, { name = "DiagnosticError", link = false })
	local diagnostic_underline = vim.api.nvim_get_hl(0, { name = "DiagnosticUnderlineError", link = false })
	assert_eq(diagnostic_error.fg, hex_to_rgb(storm.error), "TokyoNight diagnostic color ownership changed")
	assert_eq(diagnostic_underline.undercurl, true, "diagnostic error lost its non-color cue")
	assert_eq(diagnostic_underline.sp, hex_to_rgb(storm.error), "diagnostic undercurl color changed")

	local overlay = theme.highlights(storm)
	for _, host_group in ipairs({
		"Normal",
		"CursorLine",
		"DiagnosticError",
		"BlinkCmpKindFunction",
		"NeotestPassed",
		"RenderMarkdownH1",
	}) do
		assert_eq(overlay[host_group], nil, "DX overlay took ownership of host group " .. host_group)
	end

	local repo_root = vim.fs.root(0, ".git") or vim.fn.getcwd()
	local storm_contract = dofile(repo_root .. "/tests/nvim/visual_contracts/storm.lua")
	storm_contract.verify({
		palette = palette,
		roles = actual_roles,
		graph = overlay,
		domain = domain,
		host_colors = storm,
	})

	print(
		("DX-COLOR-004 M1 Storm host runtime contract passed against actual Normal.bg %s."):format(
			rgb_to_hex(normal.bg)
		)
	)
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	io.stderr:write(("\n!!! DX-COLOR-004 M1 PRODUCTION VISUAL RUNTIME FAILURE !!!\n%s\n"):format(err))
	vim.cmd("cquit 1")
end
