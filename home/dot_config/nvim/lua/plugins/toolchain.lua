local mason_tools = {
  -- Shared native debugging. clangd and clang-format come from the same
  -- rolling Homebrew LLVM toolchain as the compiler.
  "codelldb",
  "gersemi",
  -- Python
  "debugpy",
  "pyright",
  "ruff",
  "ty",
  -- Zig
  "zls",
  -- Go
  "delve",
  "gofumpt",
  "goimports",
  "golangci-lint",
  "gopls",
}

local function homebrew_llvm_tool(name)
  for _, bindir in ipairs({
    "/opt/homebrew/opt/llvm/bin",
    "/usr/local/opt/llvm/bin",
    "/home/linuxbrew/.linuxbrew/opt/llvm/bin",
  }) do
    local path = vim.fs.joinpath(bindir, name)
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
  return name
end

local function extend_unique(target, values)
  for _, value in ipairs(values) do
    if not vim.tbl_contains(target, value) then
      target[#target + 1] = value
    end
  end
end

local function unique_tools(tools)
  local result = {}
  local seen = {}
  for _, tool in ipairs(tools) do
    local name = type(tool) == "table" and tool[1] or tool
    if not seen[name] then
      seen[name] = true
      result[#result + 1] = tool
    end
  end
  return result
end

local function project_executable(subdir)
  local root = LazyVim.root()
  return vim.fn.input("Path to executable: ", vim.fs.joinpath(root, subdir), "file")
end

return {
  -- Mason owns editor-only language servers, formatters and debug adapters.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- LazyVim's CMake extra still selects the older cmakelang/cmakelint
      -- pair. Prefer actively maintained gersemi and let neocmake own
      -- diagnostics under the global 100-column policy.
      opts.ensure_installed = vim.tbl_filter(function(tool)
        return tool ~= "cmakelang" and tool ~= "cmakelint"
      end, opts.ensure_installed or {})
      extend_unique(opts.ensure_installed, mason_tools)
    end,
  },

  -- Keep C/C++ indexing and formatting on one rolling Homebrew LLVM release.
  -- Explicit paths prevent Mason's bin directory from selecting a stale clangd.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          mason = false,
          cmd = {
            homebrew_llvm_tool("clangd"),
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
            "--completion-style=detailed",
            "--fallback-style=llvm",
          },
        },
        neocmake = {
          init_options = {
            format = { enable = false },
            lint = { enable = true },
            scan_cmake_in_package = false,
            semantic_token = false,
          },
        },
        yamlls = {
          before_init = function(_, new_config)
            new_config.settings = new_config.settings or {}
            new_config.settings.yaml = new_config.settings.yaml or {}
            new_config.settings.yaml.schemas = vim.tbl_deep_extend(
              "force",
              new_config.settings.yaml.schemas or {},
              require("schemastore").yaml.schemas({
                ignore = { "clang-format (.clang-format)" },
              })
            )
          end,
        },
      },
    },
  },

  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        c = { "clang-format" },
        cpp = { "clang-format" },
        objc = { "clang-format" },
        objcpp = { "clang-format" },
        cuda = { "clang-format" },
        cmake = { "gersemi" },
      },
      formatters = {
        ["clang-format"] = {
          command = homebrew_llvm_tool("clang-format"),
        },
        gersemi = {
          prepend_args = { "--line-length", "100" },
        },
      },
    },
  },

  -- neocmake owns CMake diagnostics. Disable LazyVim's redundant legacy
  -- cmakelint process; the global neocmakelsp config keeps its internal lint
  -- engine on the same 100-column policy as gersemi.
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.cmake = {}
    end,
  },

  -- Keep the complete Mason tool set current once per day. Unlike plugins,
  -- Mason packages have no lockfile, matching this workstation's rolling
  -- latest policy. The synchronous commands are also available for CI/devup.
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    event = "VeryLazy",
    cmd = {
      "MasonToolsInstall",
      "MasonToolsInstallSync",
      "MasonToolsUpdate",
      "MasonToolsUpdateSync",
      "MasonToolsClean",
    },
    opts = {
      auto_update = true,
      run_on_start = true,
      start_delay = 3000,
      debounce_hours = 24,
    },
    config = function(_, opts)
      opts.ensure_installed = unique_tools(vim.deepcopy(LazyVim.opts("mason.nvim").ensure_installed or {}))
      require("mason-tool-installer").setup(opts)
    end,
  },

  -- Use Clippy for the richest Rust diagnostics while rust-analyzer continues
  -- to provide navigation, completion, runnables and semantic information.
  {
    "mrcjkb/rustaceanvim",
    optional = true,
    opts = {
      server = {
        default_settings = {
          ["rust-analyzer"] = {
            check = {
              command = "clippy",
              extraArgs = { "--all-targets" },
            },
          },
        },
      },
    },
  },

  -- Route configure/build/run output through the same task panel used by
  -- language-agnostic jobs. CMakeTools already supplies codelldb integration.
  {
    "Civitasv/cmake-tools.nvim",
    optional = true,
    dependencies = { "stevearc/overseer.nvim" },
    opts = {
      cmake_generate_options = {
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=1",
        "-DCMAKE_C_COMPILER_LAUNCHER=ccache",
        "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache",
      },
      cmake_executor = { name = "overseer" },
      cmake_runner = { name = "overseer" },
      cmake_dap_configuration = {
        name = "CMake target",
        type = "codelldb",
        request = "launch",
        stopOnEntry = false,
        runInTerminal = true,
        console = "integratedTerminal",
      },
    },
  },

  -- Keep test runs deterministic and make Go tests directly debuggable.
  {
    "nvim-neotest/neotest",
    optional = true,
    opts = {
      adapters = {
        ["neotest-golang"] = {
          go_test_args = { "-v", "-count=1", "-timeout=60s" },
          dap_go_enabled = true,
        },
        ["neotest-python"] = {
          runner = "pytest",
        },
      },
    },
  },

  -- LazyVim configures codelldb for C/C++ and Rust. Reuse that adapter for
  -- Zig executables so every native language shares one debugger UX.
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")
      dap.configurations.zig = {
        {
          type = "codelldb",
          request = "launch",
          name = "Launch Zig executable",
          program = function()
            return project_executable("zig-out/bin/")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          type = "codelldb",
          request = "attach",
          name = "Attach to process",
          pid = require("dap.utils").pick_process,
          cwd = "${workspaceFolder}",
        },
      }
    end,
  },

  -- ty is intentionally an on-demand whole-project check for now. Pyright
  -- remains the mature interactive LSP while ty evolves rapidly.
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>cT",
        function()
          if vim.fn.executable("ty") == 0 then
            LazyVim.warn("ty is not installed yet; run :Mason and install it", { title = "Python" })
            return
          end
          Snacks.terminal({ "ty", "check" }, { cwd = LazyVim.root() })
        end,
        desc = "Ty Check Project",
        ft = "python",
      },
    },
  },
}
