local context = require("config.python_context")

return {
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "debugpy" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          settings = {
            pyright = { disableOrganizeImports = true },
            python = {
              analysis = {
                autoImportCompletions = true,
                autoSearchPaths = true,
                diagnosticMode = "openFilesOnly",
                useLibraryCodeForTypes = true,
              },
            },
          },
          before_init = function(_, config)
            local resolved = context.resolve(config.root_dir)
            local python = resolved
              and resolved.source ~= "system"
              and resolved.source ~= "deactivated"
              and resolved.python
            if not python then
              return
            end

            config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
              python = { pythonPath = python },
            })
            config.cmd_env = vim.tbl_extend("force", config.cmd_env or {}, resolved.env)
          end,
        },
      },
    },
  },
  {
    "linux-cultist/venv-selector.nvim",
    config = function(_, opts)
      context.setup_selector(opts)
    end,
  },
  {
    "nvim-neotest/neotest",
    optional = true,
    opts = function(_, opts)
      local python = opts.adapters["neotest-python"] or {}
      opts.adapters["neotest-python"] = false
      table.insert(opts.adapters, context.neotest_adapter(python))
    end,
  },
  {
    "mfussenegger/nvim-dap-python",
    optional = true,
    config = function()
      require("dap-python").setup("debugpy-adapter")
      context.setup_dap()
    end,
  },
}
