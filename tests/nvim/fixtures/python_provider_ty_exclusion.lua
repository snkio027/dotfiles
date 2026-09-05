--- M2C-A test-only negative control.
--- Loaded only from a temporary XDG_CONFIG_HOME overlay.
return {
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				ty = { enabled = false },
			},
		},
	},
}
