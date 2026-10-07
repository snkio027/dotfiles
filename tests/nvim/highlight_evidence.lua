-- Test-only identity/foreground evidence. Neovim owns link and @capture fallback
-- resolution; colors and dotted group names are not semantic classifiers.
local M = {}

function M.role_for_group(group)
	local id = vim.api.nvim_get_hl_id_by_name(group)
	local resolved = vim.fn.synIDattr(vim.fn.synIDtrans(id), "name")
	return require("theme.domain").roles[resolved] and resolved or nil
end

function M.assert_role(group, expected, foreground)
	local observed = M.role_for_group(group)
	assert(
		expected ~= nil and observed == expected,
		("DX_IDENTITY_MISMATCH: %s -> %s, expected %s"):format(group, tostring(observed), tostring(expected))
	)
	local role_fg = vim.api.nvim_get_hl(0, { name = observed, link = false }).fg
	assert(
		type(role_fg) == "number" and foreground == role_fg,
		("DX_FOREGROUND_MISMATCH: %s -> %s, actual %s, expected %s"):format(
			group,
			observed,
			tostring(foreground),
			tostring(role_fg)
		)
	)
	return observed
end

return M
