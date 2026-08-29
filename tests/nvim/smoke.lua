local function contains(values, expected)
	return vim.tbl_contains(values or {}, expected)
end

assert(vim.fn.exists(":OverseerRun") == 2, "Overseer command is unavailable")
assert(vim.fn.exists(":MasonToolsInstallSync") == 2, "Mason tool installer command is unavailable")

local mason = LazyVim.opts("mason.nvim")
for _, tool in ipairs({
	"codelldb",
	"gersemi",
	"debugpy",
	"pyright",
	"ruff",
	"sqlfluff",
	"ty",
	"zls",
	"delve",
	"gopls",
}) do
	assert(contains(mason.ensure_installed, tool), ("Mason tool is missing: %s"):format(tool))
end
assert(not contains(mason.ensure_installed, "clangd"), "Mason must not shadow Homebrew clangd")
assert(not contains(mason.ensure_installed, "clang-format"), "Mason must not shadow Homebrew clang-format")
assert(not contains(mason.ensure_installed, "cmakelang"), "Obsolete cmakelang should not be installed")
assert(not contains(mason.ensure_installed, "cmakelint"), "Obsolete cmakelint should not be installed")

require("lazy").load({ plugins = { "mason.nvim" } })
for _, executable in ipairs({
	"codelldb",
	"gersemi",
	"debugpy",
	"pyright",
	"ruff",
	"sqlfluff",
	"ty",
	"zls",
	"dlv",
	"gofumpt",
	"goimports",
	"golangci-lint",
	"gopls",
}) do
	assert(vim.fn.executable(executable) == 1, ("Mason executable is unavailable: %s"):format(executable))
end

local lsp = LazyVim.opts("nvim-lspconfig")
local clangd = lsp.servers.clangd
assert(clangd.mason == false, "Homebrew clangd must be enabled outside Mason")
assert(clangd.cmd[1]:match("/opt/llvm/bin/clangd$"), "clangd is not from Homebrew LLVM")
assert(vim.fn.executable(clangd.cmd[1]) == 1, "Homebrew clangd is unavailable")
assert(not contains(clangd.cmd, "--function-arg-placeholders"), "clangd has an invalid placeholders flag")
assert(lsp.servers.neocmake.init_options.lint.enable, "neocmake lint is disabled")
assert(not lsp.servers.neocmake.init_options.format.enable, "neocmake competes with gersemi formatting")

local config_home = vim.env.XDG_CONFIG_HOME or vim.fs.dirname(vim.fn.stdpath("config"))
local neocmake_config = config_home .. "/neocmakelsp/config.toml"
local neocmake_config_lines = vim.fn.readfile(neocmake_config)
assert(contains(neocmake_config_lines, "line_max_words = 100"), "neocmake line length is not 100 columns")
assert(contains(neocmake_config_lines, "enable_external_cmake_lint = false"), "neocmake external cmake-lint is enabled")

local conform = LazyVim.opts("conform.nvim")
local clang_format = conform.formatters["clang-format"].command
assert(clang_format:match("/opt/llvm/bin/clang%-format$"), "clang-format is not from Homebrew LLVM")
assert(vim.fn.executable(clang_format) == 1, "Homebrew clang-format is unavailable")
assert(contains(conform.formatters_by_ft.cmake, "gersemi"), "CMake is not formatted by gersemi")
assert(contains(conform.formatters.gersemi.prepend_args, "100"), "CMake line length is not 100 columns")

local lint = LazyVim.opts("nvim-lint")
assert(vim.tbl_isempty(lint.linters_by_ft.cmake), "Redundant external cmakelint is still enabled")

local function llvm_major(command)
	local output = vim.fn.system({ command, "--version" })
	assert(vim.v.shell_error == 0, ("Unable to query %s"):format(command))
	return output:match("version%s+(%d+)")
end

assert(llvm_major(clangd.cmd[1]) == llvm_major(clang_format), "clangd and clang-format versions differ")

require("lazy").load({ plugins = { "nvim-lspconfig" } })
assert(vim.lsp.is_enabled("clangd"), "Homebrew clangd is configured but not enabled")

require("lazy").load({ plugins = { "SchemaStore.nvim" } })
local yaml_config = { settings = { yaml = { schemas = {} } } }
lsp.servers.yamlls.before_init(nil, yaml_config)
for _, matches in pairs(yaml_config.settings.yaml.schemas) do
	for _, pattern in ipairs(type(matches) == "table" and matches or { matches }) do
		assert(pattern ~= ".clang-format", "Obsolete clang-format schema is still enabled")
	end
end

local rust = LazyVim.opts("rustaceanvim")
local rust_analyzer = rust.server.default_settings["rust-analyzer"]
assert(rust_analyzer.check.command == "clippy", "rust-analyzer is not using Clippy")

local cmake = LazyVim.opts("cmake-tools.nvim")
assert(contains(cmake.cmake_generate_options, "-DCMAKE_EXPORT_COMPILE_COMMANDS=1"), "CMake compile DB is disabled")
assert(contains(cmake.cmake_generate_options, "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"), "CMake is not using ccache")
assert(cmake.cmake_executor.name == "overseer", "CMake executor is not Overseer")
assert(cmake.cmake_runner.name == "overseer", "CMake runner is not Overseer")
assert(cmake.cmake_dap_configuration.type == "codelldb", "CMake debugger is not codelldb")

local neotest = LazyVim.opts("neotest")
assert(neotest.adapters["neotest-golang"].dap_go_enabled, "Go tests are not debuggable")
assert(neotest.adapters["neotest-python"].runner == "pytest", "Python tests are not using pytest")

require("lazy").load({ plugins = { "nvim-dap" } })
local dap = require("dap")
assert(dap.adapters.codelldb, "codelldb adapter is unavailable")
assert(#(dap.configurations.zig or {}) >= 2, "Zig launch/attach configurations are unavailable")

print("Neovim toolchain smoke tests passed")
