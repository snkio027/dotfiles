local function uv_python(source)
  if not source then
    return nil
  end

  local root = vim.fs.root(source, "uv.lock")
  if not root then
    return nil
  end

  local python = vim.fs.joinpath(root, ".venv", "bin", "python")
  return vim.fn.executable(python) == 1 and python or nil
end

local function activate_uv_venv(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "python" then
    return
  end

  local python = uv_python(buf)
  local selector = require("venv-selector")
  if python and selector.python() ~= python then
    vim.api.nvim_buf_call(buf, function()
      -- A standard uv project uses a regular .venv; the "uv" selector type is
      -- reserved for PEP 723 script environments and intentionally unsets VIRTUAL_ENV.
      selector.activate_from_path(python, "venv")
    end)
  end
end

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
            local python = uv_python(config.root_dir)
            if not python then
              return
            end

            config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
              python = { pythonPath = python },
            })
            config.cmd_env = vim.tbl_extend("force", config.cmd_env or {}, {
              VIRTUAL_ENV = vim.fs.dirname(vim.fs.dirname(python)),
            })
          end,
        },
      },
    },
  },
  {
    "linux-cultist/venv-selector.nvim",
    config = function(_, opts)
      require("venv-selector").setup(opts)

      local group = vim.api.nvim_create_augroup("dotfiles_uv_venv", { clear = true })
      local function schedule_activation(args)
        vim.schedule(function()
          activate_uv_venv(args.buf)
        end)
      end
      vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = "*.py",
        callback = schedule_activation,
      })
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "python",
        callback = schedule_activation,
      })

      -- The plugin itself is loaded by the first Python FileType event, so that
      -- event has already fired when this configuration function runs.
      vim.schedule(function()
        activate_uv_venv(vim.api.nvim_get_current_buf())
      end)
    end,
  },
}
