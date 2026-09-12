return {
  {
    "rcarriga/nvim-dap-ui",
    enabled = false,
  },
  {
    "mfussenegger/nvim-dap",
    dependencies = { "igorlfs/nvim-dap-view" },
  },
  {
    "igorlfs/nvim-dap-view",
    version = "v1.2.1",
    opts = {
      auto_toggle = true,
      windows = {
        position = "below",
        size = 0.25,
      },
    },
    keys = {
      {
        "<leader>du",
        function()
          require("dap-view").toggle()
        end,
        desc = "Dap View",
      },
      {
        "<leader>de",
        function()
          require("dap-view").hover(nil, true)
        end,
        desc = "Eval",
        mode = { "n", "x" },
      },
    },
  },
}
