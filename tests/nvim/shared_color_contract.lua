-- Called by the existing Tier-1 contract; all highlight mutations are restored.
return function(groups)
	local root = vim.fs.root(0, ".git") or vim.fn.getcwd()
	local evidence = dofile(root .. "/tests/nvim/highlight_evidence.lua")
	local saved = {}
	local function set(group, spec)
		if saved[group] == nil then
			saved[group] = vim.api.nvim_get_hl(0, { name = group, link = true, create = false })
		end
		vim.api.nvim_set_hl(0, group, spec)
	end
	local function fg(group)
		return vim.api.nvim_get_hl(0, { name = group, link = false }).fg
	end
	local function rejects(callback, marker)
		local ok, err = pcall(callback)
		assert(not ok and tostring(err):find(marker, 1, true), "Negative control did not reject: " .. marker)
	end
	local ok, err = xpcall(function()
		for _, pair in ipairs({
			{ "DxKeyword", "DxFunctionKeyword", "#DB8FEE", "@keyword", "@keyword.function" },
			{ "DxConstant", "DxNumber", "#F2D675", "@constant", "@number" },
		}) do
			for index = 1, 2 do
				local role, group = pair[index], pair[index + 3]
				local spec = vim.deepcopy(groups[role])
				spec.fg = pair[3]
				set(role, spec)
				set(group, groups[group])
			end
			assert(fg(pair[4]) == fg(pair[5]), "Shared-color setup failed")
			for index = 1, 2 do
				local role, group = pair[index], pair[index + 3]
				evidence.assert_role(group, role, fg(group))
				-- Exercise Neovim's real dotted fallback, not a hand-made path guess.
				local child = group .. ".dx_e_shared_test"
				evidence.assert_role(child, role, fg(child))
			end
			-- Same rendered RGB must not conceal function-keyword -> keyword or
			-- numeric-literal -> constant misclassification.
			set(pair[5], { link = pair[1] })
			assert(fg(pair[5]) == fg(pair[4]), "Wrong-link control changed RGB")
			rejects(function()
				evidence.assert_role(pair[5], pair[2], fg(pair[5]))
			end, "DX_IDENTITY_MISMATCH")
			set(pair[5], groups[pair[5]])
		end
		set("@lsp.type.number", groups["@lsp.type.number"])
		set("@lsp.type.enumMember", groups["@lsp.type.enumMember"])
		evidence.assert_role("@lsp.type.number", "DxNumber", fg("@lsp.type.number"))
		evidence.assert_role("@lsp.type.enumMember", "DxConstant", fg("@lsp.type.enumMember"))
		-- Direct child attributes do not inherit their parent's semantic identity,
		-- even when the RGB happens to match. Also retain independent fg evidence.
		local direct = "@number.dx_e_direct_test"
		for _, color in ipairs({ "#F2D675", "#FF0000" }) do
			set(direct, { fg = color })
			rejects(function()
				evidence.assert_role(direct, "DxNumber", fg(direct))
			end, "DX_IDENTITY_MISMATCH")
		end
		rejects(function()
			evidence.assert_role("@number", "DxNumber", 0xFF0000)
		end, "DX_FOREGROUND_MISMATCH")
	end, debug.traceback)
	for group, spec in pairs(saved) do
		vim.api.nvim_set_hl(0, group, spec)
		assert(vim.deep_equal(vim.api.nvim_get_hl(0, { name = group, link = true }), spec), "Restore drift: " .. group)
	end
	assert(ok, err)
	print(
		"Shared-color identity contract passed: keyword/function-keyword and number/constant; wrong links and foregrounds rejected."
	)
end
