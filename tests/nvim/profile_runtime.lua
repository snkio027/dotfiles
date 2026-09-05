--- DX-COLOR-003 M3-C production runtime profile-selection contract.

local function main()
	local function fail(message)
		error("PROFILE_RUNTIME_CONTRACT_FAILURE: " .. message, 2)
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

	local test_case = vim.g.dx_color_profile_case
	if test_case ~= "default" and test_case ~= "opt-in" and test_case ~= "opt-out" and test_case ~= "invalid-false" then
		fail("test harness must declare default, opt-in, opt-out, or invalid-false in g:dx_color_profile_case")
	end

	local theme = require("theme")
	if test_case == "invalid-false" then
		assert_eq(vim.g.dx_color_profile, false, "invalid-false test must preserve the raw false override")
		local accepted, rejection = pcall(theme.active_profile)
		if accepted then
			fail("production runtime silently accepted the false selector")
		end
		if not tostring(rejection):find("expected one of: c3_1, c4", 1, true) then
			fail("false selector rejection did not name the accepted profiles: " .. tostring(rejection))
		end
		io.stderr:write(tostring(rejection) .. "\n")
		print("M3-C invalid false selector rejected by production runtime.")
		vim.cmd("cquit 1")
		return
	end

	local expected_profile = vim.g.dx_color_expected_profile
	if expected_profile ~= "c3_1" and expected_profile ~= "c4" then
		fail("test harness must declare c3_1 or c4 in g:dx_color_expected_profile")
	end
	local colorscheme = vim.g.colors_name
	if colorscheme ~= "catppuccin" and colorscheme ~= "catppuccin-mocha" then
		fail(("Catppuccin production colorscheme is not active: %s"):format(vim.inspect(colorscheme)))
	end

	local selected_profile, visual = theme.active_profile()
	assert_eq(selected_profile, expected_profile, "runtime selected the wrong visual profile")
	local expected_override
	if test_case ~= "default" then
		expected_override = expected_profile
	end
	assert_eq(vim.g.dx_color_profile, expected_override, "runtime raw profile override drifted")

	local catppuccin = require("catppuccin.palettes").get_palette("mocha")
	if type(catppuccin) ~= "table" then
		fail("Catppuccin Mocha palette is unavailable")
	end
	local palette = require("theme.palette").resolve(catppuccin, selected_profile)
	local domain = require("theme.domain")
	local expected_roles = visual.roles(palette)
	local actual_roles = {}

	for role in pairs(domain.roles) do
		local expected = expected_roles[role]
		local actual = vim.api.nvim_get_hl(0, { name = role, link = false })
		if type(expected) ~= "table" or type(expected.fg) ~= "string" then
			fail("selected profile is missing a concrete foreground for " .. role)
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
	local expected_background = palette.ui.normal_bg or palette.ui.base
	assert_eq(
		resolved_background:lower(),
		expected_background:lower(),
		"runtime selected profile resolved the wrong Normal background"
	)
	if selected_profile == "c4" then
		local c4_contract = dofile((vim.fs.root(0, ".git") or vim.fn.getcwd()) .. "/tests/nvim/visual_contracts/c4.lua")
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
		print(("M3-C runtime C4 contrast contract passed against actual Normal.bg %s."):format(resolved_background))
	end

	print(("M3-C runtime profile selection passed: %s -> %s."):format(test_case, selected_profile))
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	io.stderr:write(("\n!!! M3-C PROFILE RUNTIME FAILURE !!!\n%s\n"):format(tostring(err)))
	vim.api.nvim_err_writeln(("M3-C PROFILE RUNTIME FAILURE: %s"):format(tostring(err)))
	vim.cmd("cquit 1")
end
