return {
  {
    "nvim-neotest/neotest",
    optional = true,
    opts = function(_, opts)
      if opts.adapters and opts.adapters["neotest-zig"] ~= nil then
        opts.adapters["neotest-zig"] = false
        table.insert(opts.adapters, require("config.zig_test").adapter())
      end
    end,
  },
  {
    "mfussenegger/nvim-dap",
    init = function()
      vim.api.nvim_create_user_command("ZigBuildDebug", function()
        require("config.zig_debug").build_debug()
      end, { desc = "Build then debug the explicit Zig project target" })
      vim.api.nvim_create_user_command("ZigBuildDebugOutput", function()
        require("config.zig_debug").output()
      end, { desc = "Show the latest Zig build output" })
      vim.api.nvim_create_user_command("ZigBuildDebugStop", function()
        require("config.zig_debug").stop()
      end, { desc = "Cancel the pending Zig build and debugger launch" })
    end,
    keys = {
      {
        "<leader>oZ",
        function()
          require("config.zig_debug").build_debug()
        end,
        desc = "Build and Debug (Zig Project)",
        ft = "zig",
      },
    },
  },
}
