local case = vim.env.DOTFILES_NATIVE_FIRST_CASE
local flavours = {
	["native-mocha"] = "mocha",
	["native-macchiato"] = "macchiato",
	["native-frappe"] = "frappe",
}

local flavour = flavours[case]
if not flavour then
	error("NATIVE_FIRST_OVERRIDE_FAILURE: unsupported native case " .. tostring(case))
end

return {
	{
		"catppuccin/nvim",
		opts = function(_, opts)
			opts.flavour = flavour
			-- E1 observes Catppuccin itself. Keep the production UX options and
			-- integration set, but remove the M5 source/UI projection wholesale.
			opts.custom_highlights = nil
			return opts
		end,
	},
}
