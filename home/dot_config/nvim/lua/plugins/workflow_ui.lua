return {
  {
    "stevearc/overseer.nvim",
    optional = true,
    keys = {
      { "<leader>oA", "<cmd>OverseerTaskAction<cr>", desc = "Task Action (Overseer)" },
      {
        "<leader>oE",
        function()
          require("config.task_output").export()
        end,
        desc = "Export Task Output",
      },
    },
  },
  {
    "folke/which-key.nvim",
    opts = { spec = { { "<leader>o", group = "build / tasks" } } },
  },
  {
    "pwntester/octo.nvim",
    keys = {
      { "<leader>gS", false },
      { "<leader>g/", "<cmd>Octo search<cr>", desc = "Search GitHub (Octo)" },
    },
  },
  {
    "nvim-neotest/neotest",
    opts = {
      -- The built-in consumer replaces the user's current quickfix list.
      quickfix = { enabled = false },
      -- LazyVim adds this consumer in config(); its unscoped close can affect
      -- diagnostics/references. Neotest honors enabled for custom consumers too.
      trouble = { enabled = false },
      consumers = {
        dotfiles_results = function(client)
          return require("config.test_results").consumer(client)
        end,
      },
    },
    keys = {
      {
        "<leader>tq",
        function()
          require("config.test_results").open()
        end,
        desc = "Failed Tests (Trouble)",
      },
    },
  },
}
