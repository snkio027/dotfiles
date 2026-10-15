-- Opt-in candidate only: copy into the isolated config's lua/plugins directory.
-- Do not import LazyVim's Sidekick extra: it also changes NES/Tab integration.
return {
	{
		"folke/sidekick.nvim",
		commit = "3d80a47e6375f6d647c9695d3afea6fa1b3275df",
		opts = {
			nes = { enabled = false },
			cli = {
				mux = { enabled = false },
				tools = {
					codex = {
						-- Model, authentication and other settings remain owned by Codex.
						cmd = { "codex", "--sandbox", "workspace-write", "--ask-for-approval", "on-request" },
					},
				},
			},
		},
		keys = {
			{
				"<leader>aa",
				function()
					require("sidekick.cli").show({ name = "codex", focus = true })
				end,
				desc = "Codex: Open / Focus (Trial)",
			},
			{
				"<leader>as",
				function()
					local visual = vim.fn.mode():match("[vV\22]") ~= nil
					require("sidekick.cli").send({
						name = "codex",
						msg = visual and "{file}\n{selection}" or "{this}",
						submit = false,
						focus = true,
					})
				end,
				mode = { "n", "x" },
				desc = "Codex: Draft Context (Trial)",
			},
			{
				"<leader>ad",
				function()
					require("sidekick.cli").send({
						name = "codex",
						msg = "Explain the root cause of these diagnostics first. Do not modify files.\n{file}\n{diagnostics}",
						submit = false,
						focus = true,
					})
				end,
				desc = "Codex: Draft File Diagnostics (Trial)",
			},
		},
	},
}
